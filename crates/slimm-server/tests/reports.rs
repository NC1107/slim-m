// SPDX-License-Identifier: AGPL-3.0-only
//! Report triage: MANAGE_MESSAGES gates both the queue and resolving one, and
//! nobody below that bar ever sees a report's content snapshot.

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

async fn new_store() -> Store {
    let path = format!("/tmp/slimm-reports-test-{}.db", Uuid::now_v7());
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        push_relay_url: None,
        push_relay_key: None,
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    Store::new(pool)
}

fn app(store: Store) -> Router {
    http::router(AppState {
        store,
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
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

async fn general_channel_id(store: &Store) -> String {
    store
        .list_channels()
        .await
        .unwrap()
        .into_iter()
        .next()
        .expect("bootstrap seeds a general channel")
        .id
        .to_string()
}

/// Sends a message as `token` and files a report on it as `reporter_token`,
/// returning the report id.
async fn file_a_report(
    app: &Router,
    channel_id: &str,
    author_token: &str,
    reporter_token: &str,
    content: &str,
) -> String {
    let sent = json_body(
        app.clone()
            .oneshot(request(
                "POST",
                &format!("/channels/{channel_id}/messages"),
                Some(author_token),
                Some(json!({ "id": Uuid::now_v7().to_string(), "content": content })),
            ))
            .await
            .unwrap(),
    )
    .await;
    let message_id = sent["id"].as_str().unwrap();

    let filed = app
        .clone()
        .oneshot(request(
            "POST",
            "/reports",
            Some(reporter_token),
            Some(json!({
                "subject_kind": "message",
                "subject_id": message_id,
                "reason": "spam"
            })),
        ))
        .await
        .unwrap();
    assert_eq!(filed.status(), StatusCode::OK);
    json_body(filed).await["id"].as_str().unwrap().to_owned()
}

// ---------------------------------------------------------------------------
// Gating
// ---------------------------------------------------------------------------

#[tokio::test]
async fn listing_and_resolving_require_manage_messages() {
    let store = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let (bob_token, _bob_id) = register(&store, "bob").await;
    let (carol_token, _carol_id) = register(&store, "carol").await;
    let channel_id = general_channel_id(&store).await;
    let report_id = file_a_report(
        &app,
        &channel_id,
        &bob_token,
        &carol_token,
        "secret content",
    )
    .await;

    let list = app
        .clone()
        .oneshot(request("GET", "/reports", Some(&bob_token), None))
        .await
        .unwrap();
    assert_eq!(list.status(), StatusCode::FORBIDDEN);

    let resolve = app
        .clone()
        .oneshot(request(
            "PATCH",
            &format!("/reports/{report_id}"),
            Some(&bob_token),
            Some(json!({ "resolution": "resolved" })),
        ))
        .await
        .unwrap();
    assert_eq!(resolve.status(), StatusCode::FORBIDDEN);

    // An administrator (MANAGE_MESSAGES via ADMINISTRATOR) can do both.
    let admin_list = app
        .clone()
        .oneshot(request("GET", "/reports", Some(&admin_token), None))
        .await
        .unwrap();
    assert_eq!(admin_list.status(), StatusCode::OK);
}

// ---------------------------------------------------------------------------
// Happy path and the queue's lifecycle
// ---------------------------------------------------------------------------

#[tokio::test]
async fn the_queue_carries_the_snapshot_and_resolving_removes_it() {
    let store = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let (bob_token, _bob_id) = register(&store, "bob").await;
    let (carol_token, _carol_id) = register(&store, "carol").await;
    let channel_id = general_channel_id(&store).await;
    let report_id = file_a_report(
        &app,
        &channel_id,
        &bob_token,
        &carol_token,
        "the reported text",
    )
    .await;

    let listed = json_body(
        app.clone()
            .oneshot(request("GET", "/reports", Some(&admin_token), None))
            .await
            .unwrap(),
    )
    .await;
    let reports = listed.as_array().unwrap();
    assert_eq!(reports.len(), 1);
    assert_eq!(reports[0]["id"], report_id);
    assert_eq!(reports[0]["snapshot"], "the reported text");
    assert_eq!(reports[0]["subject_kind"], "message");
    assert_eq!(reports[0]["reason"], "spam");

    let resolve = app
        .clone()
        .oneshot(request(
            "PATCH",
            &format!("/reports/{report_id}"),
            Some(&admin_token),
            Some(json!({ "resolution": "resolved" })),
        ))
        .await
        .unwrap();
    assert_eq!(resolve.status(), StatusCode::NO_CONTENT);

    let after = json_body(
        app.clone()
            .oneshot(request("GET", "/reports", Some(&admin_token), None))
            .await
            .unwrap(),
    )
    .await;
    assert!(
        after.as_array().unwrap().is_empty(),
        "a resolved report leaves the open queue"
    );

    // Resolving it again finds nothing left to close.
    let again = app
        .clone()
        .oneshot(request(
            "PATCH",
            &format!("/reports/{report_id}"),
            Some(&admin_token),
            Some(json!({ "resolution": "dismissed" })),
        ))
        .await
        .unwrap();
    assert_eq!(again.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn resolution_must_be_resolved_or_dismissed() {
    let store = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let (bob_token, _bob_id) = register(&store, "bob").await;
    let (carol_token, _carol_id) = register(&store, "carol").await;
    let channel_id = general_channel_id(&store).await;
    let report_id = file_a_report(&app, &channel_id, &bob_token, &carol_token, "x").await;

    let response = app
        .clone()
        .oneshot(request(
            "PATCH",
            &format!("/reports/{report_id}"),
            Some(&admin_token),
            Some(json!({ "resolution": "ignored" })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn resolving_a_nonexistent_report_is_not_found() {
    let store = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "PATCH",
            &format!("/reports/{}", Uuid::now_v7()),
            Some(&admin_token),
            Some(json!({ "resolution": "resolved" })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}
