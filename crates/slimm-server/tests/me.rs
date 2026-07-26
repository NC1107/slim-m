// SPDX-License-Identifier: AGPL-3.0-only
//! The caller's own profile: reading it with effective base permissions, and
//! updating the display name (and only the display name).

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::permissions::Permissions;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use tower::ServiceExt;
use uuid::Uuid;

async fn new_store() -> Store {
    let path = std::env::temp_dir()
        .join(format!("slimm-me-test-{}.db", Uuid::now_v7()))
        .to_string_lossy()
        .into_owned();
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

async fn register(app: &Router, username: &str) -> (String, String) {
    let response = app
        .clone()
        .oneshot(request(
            "POST",
            "/auth/register",
            None,
            Some(json!({
                "username": username,
                "display_name": username,
                "password": "hunter2hunter2",
                "device_name": "cli"
            })),
        ))
        .await
        .unwrap();
    let body = json_body(response).await;
    (
        body["access_token"].as_str().unwrap().to_owned(),
        body["user_id"].as_str().unwrap().to_owned(),
    )
}

/// `/me` echoes the caller's own profile plus their effective base
/// permissions, so a client can decide which actions to show.
#[tokio::test]
async fn get_me_returns_profile_and_base_permissions() {
    let store = new_store().await;
    let app = app(store);
    // No role pre-created: the first account to register claims the
    // unclaimed deployment and is granted an administrator role.
    let (token, user_id) = register(&app, "alice").await;

    let response = app
        .clone()
        .oneshot(request("GET", "/me", Some(&token), None))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = json_body(response).await;

    assert_eq!(body["id"], user_id);
    assert_eq!(body["username"], "alice");
    assert_eq!(body["display_name"], "alice");

    // The first account to register claims the deployment and becomes an
    // administrator, so its base permissions carry ADMINISTRATOR.
    let permissions = body["permissions"].as_i64().unwrap();
    assert_eq!(
        permissions & Permissions::ADMINISTRATOR.bits(),
        Permissions::ADMINISTRATOR.bits()
    );
}

#[tokio::test]
async fn get_me_requires_authentication() {
    let store = new_store().await;
    let app = app(store);

    let response = app
        .clone()
        .oneshot(request("GET", "/me", None, None))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn patch_me_updates_the_display_name() {
    let store = new_store().await;
    let app = app(store);
    let (token, _user_id) = register(&app, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "PATCH",
            "/me",
            Some(&token),
            Some(json!({ "display_name": "Alice In Wonderland" })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = json_body(response).await;
    assert_eq!(body["display_name"], "Alice In Wonderland");
    // The username is unchanged; this endpoint has no field for it at all.
    assert_eq!(body["username"], "alice");

    // The change is durable: a fresh read shows it too.
    let me = json_body(
        app.clone()
            .oneshot(request("GET", "/me", Some(&token), None))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(me["display_name"], "Alice In Wonderland");
}

/// A `username` field in the body has no effect: the endpoint has no such
/// field, so it cannot be used to rename the account.
#[tokio::test]
async fn patch_me_cannot_change_the_username() {
    let store = new_store().await;
    let app = app(store);
    let (token, _user_id) = register(&app, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "PATCH",
            "/me",
            Some(&token),
            Some(json!({ "display_name": "Alice", "username": "totally-different" })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = json_body(response).await;
    assert_eq!(body["username"], "alice");
}

#[tokio::test]
async fn patch_me_rejects_a_whitespace_only_name() {
    let store = new_store().await;
    let app = app(store);
    let (token, _user_id) = register(&app, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "PATCH",
            "/me",
            Some(&token),
            Some(json!({ "display_name": "   " })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn patch_me_rejects_a_name_that_is_too_long() {
    let store = new_store().await;
    let app = app(store);
    let (token, _user_id) = register(&app, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "PATCH",
            "/me",
            Some(&token),
            Some(json!({ "display_name": "x".repeat(65) })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}
