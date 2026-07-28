// SPDX-License-Identifier: AGPL-3.0-only
//! Admin-issued password reset: issuing requires ADMINISTRATOR, consuming is
//! public but single-use, and a successful consumption revokes every session
//! that predates it.

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use tower::ServiceExt;
use uuid::Uuid;

mod support;

async fn new_store() -> (Store, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new("slimm-recovery-test");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    (Store::new(pool), guard)
}

fn app(store: Store) -> Router {
    http::router(AppState {
        store,
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: slimm_server::voice::VoiceService::disabled(),
        media: slimm_server::media::Media::for_tests(),
    })
}

fn request(method: &str, uri: &str, token: Option<&str>, body: Option<Value>) -> Request<Body> {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    match body {
        Some(value) => builder
            .header("content-type", "application/json")
            .body(Body::from(value.to_string()))
            .unwrap(),
        None => builder.body(Body::empty()).unwrap(),
    }
}

async fn json_body(response: axum::response::Response) -> Value {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

/// A member with a session, built straight through the store.
///
/// Deliberately not the `/auth/register` route: joining a claimed deployment
/// is an invite-gated policy decision, and it is pinned by its own tests in
/// `registration_gate.rs`. These tests only need somebody signed in, so going
/// through the store keeps them independent of that policy.
async fn register(store: &Store, username: &str) -> (String, String) {
    let account = store
        .create_account(username, username, "not-a-real-hash")
        .await
        .unwrap();
    // The first account through here claims the deployment, exactly as the
    // first real registration does; later ones find it already set up.
    store.bootstrap_deployment(account.id).await.unwrap();
    let tokens = store.open_session(account.id, "cli").await.unwrap();
    (tokens.access_token, account.id.to_string())
}

async fn issue_code(app: &Router, admin_token: &str, user_id: &str) -> String {
    let response = app
        .clone()
        .oneshot(request(
            "POST",
            &format!("/admin/users/{user_id}/reset-code"),
            Some(admin_token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    json_body(response).await["code"]
        .as_str()
        .unwrap()
        .to_owned()
}

// --- Issuing ---

#[tokio::test]
async fn only_an_administrator_can_issue_a_code() {
    let (store, _guard) = new_store().await;
    let app = app(store.clone());
    let (_admin_token, _admin_id) = register(&store, "alice").await;
    let (member_token, member_id) = register(&store, "bob").await;

    let response = app
        .clone()
        .oneshot(request(
            "POST",
            &format!("/admin/users/{member_id}/reset-code"),
            Some(&member_token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn issuing_for_a_nonexistent_user_is_not_found() {
    let (store, _guard) = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "POST",
            &format!("/admin/users/{}/reset-code", Uuid::now_v7()),
            Some(&admin_token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

// --- Consuming ---

#[tokio::test]
async fn a_wrong_code_is_refused() {
    let (store, _guard) = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let (_bob_token, bob_id) = register(&store, "bob").await;
    let _ = issue_code(&app, &admin_token, &bob_id).await;

    let response = app
        .clone()
        .oneshot(request(
            "POST",
            "/auth/reset",
            None,
            Some(json!({ "code": "not-the-real-code", "new_password": "newhunter2newhunter2" })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn a_weak_new_password_is_rejected() {
    let (store, _guard) = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let (_bob_token, bob_id) = register(&store, "bob").await;
    let code = issue_code(&app, &admin_token, &bob_id).await;

    let response = app
        .clone()
        .oneshot(request(
            "POST",
            "/auth/reset",
            None,
            Some(json!({ "code": code, "new_password": "short" })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

/// Consuming a code sets the new password, revokes every session that
/// predates it (an old access token stops resolving), and the account is
/// reachable again only by logging in with the new password.
#[tokio::test]
async fn consuming_revokes_old_sessions_and_sets_the_new_password() {
    let (store, _guard) = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let (bob_token, bob_id) = register(&store, "bob").await;

    let still_valid = app
        .clone()
        .oneshot(request("GET", "/me", Some(&bob_token), None))
        .await
        .unwrap();
    assert_eq!(still_valid.status(), StatusCode::OK);

    let code = issue_code(&app, &admin_token, &bob_id).await;
    let reset = app
        .clone()
        .oneshot(request(
            "POST",
            "/auth/reset",
            None,
            Some(json!({ "code": code, "new_password": "newhunter2newhunter2" })),
        ))
        .await
        .unwrap();
    assert_eq!(reset.status(), StatusCode::NO_CONTENT);

    let revoked = app
        .clone()
        .oneshot(request("GET", "/me", Some(&bob_token), None))
        .await
        .unwrap();
    assert_eq!(
        revoked.status(),
        StatusCode::UNAUTHORIZED,
        "the pre-reset access token must stop resolving"
    );

    let old_password_login = app
        .clone()
        .oneshot(request(
            "POST",
            "/auth/login",
            None,
            Some(json!({
                "username": "bob",
                "password": "hunter2hunter2",
                "device_name": "cli"
            })),
        ))
        .await
        .unwrap();
    assert_eq!(old_password_login.status(), StatusCode::UNAUTHORIZED);

    let new_password_login = app
        .clone()
        .oneshot(request(
            "POST",
            "/auth/login",
            None,
            Some(json!({
                "username": "bob",
                "password": "newhunter2newhunter2",
                "device_name": "cli"
            })),
        ))
        .await
        .unwrap();
    assert_eq!(new_password_login.status(), StatusCode::OK);
}

/// A code is single-use: a second redemption, even with the right code, is
/// refused the same way a wrong code is.
#[tokio::test]
async fn a_code_cannot_be_redeemed_twice() {
    let (store, _guard) = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let (_bob_token, bob_id) = register(&store, "bob").await;
    let code = issue_code(&app, &admin_token, &bob_id).await;

    let first = app
        .clone()
        .oneshot(request(
            "POST",
            "/auth/reset",
            None,
            Some(json!({ "code": code, "new_password": "newhunter2newhunter2" })),
        ))
        .await
        .unwrap();
    assert_eq!(first.status(), StatusCode::NO_CONTENT);

    let second = app
        .clone()
        .oneshot(request(
            "POST",
            "/auth/reset",
            None,
            Some(json!({ "code": code, "new_password": "yetanotherpassword" })),
        ))
        .await
        .unwrap();
    assert_eq!(second.status(), StatusCode::BAD_REQUEST);
}
