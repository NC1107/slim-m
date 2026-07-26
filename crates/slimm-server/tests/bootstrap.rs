// SPDX-License-Identifier: AGPL-3.0-only
//! Tests for first-run bootstrap and the channel routes, including the full
//! register-to-message flow a fresh deployment must support.

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
use slimm_server::store::{Bootstrap, Store};
use tower::ServiceExt;
use uuid::Uuid;

async fn new_store() -> Store {
    let path = std::env::temp_dir()
        .join(format!("slimm-boot-test-{}.db", uuid::Uuid::now_v7()))
        .to_string_lossy()
        .into_owned();
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        push_relay_url: None,
        push_relay_key: None,
        livekit_url: None,
        livekit_api_key: None,
        livekit_api_secret: None,
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
        voice: slimm_server::voice::VoiceService::disabled(),
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

/// Registers the account that claims the deployment. Only valid first: a
/// claimed deployment takes an invite (see [`join`]).
async fn register(app: &Router, username: &str) -> String {
    signup(app, username, None).await
}

/// Joins an already-claimed deployment, minting an invite with `host`'s token
/// the way a real member gets in.
async fn join(app: &Router, host: &str, username: &str) -> String {
    let created = app
        .clone()
        .oneshot(request("POST", "/invites", Some(host), Some(json!({}))))
        .await
        .unwrap();
    assert_eq!(created.status(), StatusCode::OK);
    let code = json_body(created).await["code"]
        .as_str()
        .unwrap()
        .to_owned();
    signup(app, username, Some(&code)).await
}

async fn signup(app: &Router, username: &str, invite_code: Option<&str>) -> String {
    let mut body = json!({
        "username": username,
        "display_name": username,
        "password": "hunter2hunter2",
        "device_name": "cli"
    });
    if let Some(code) = invite_code {
        body["invite_code"] = json!(code);
    }
    let response = app
        .clone()
        .oneshot(request("POST", "/auth/register", None, Some(body)))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    json_body(response).await["access_token"]
        .as_str()
        .unwrap()
        .to_owned()
}

#[tokio::test]
async fn first_account_claims_the_deployment_and_can_message() {
    let store = new_store().await;
    assert!(!store.is_bootstrapped().await.unwrap());
    let app = app(store.clone());

    // Registering the first account seeds roles and a general channel.
    let admin = register(&app, "alice").await;
    assert!(store.is_bootstrapped().await.unwrap());

    // That account can see the seeded channel.
    let channels = json_body(
        app.clone()
            .oneshot(request("GET", "/channels", Some(&admin), None))
            .await
            .unwrap(),
    )
    .await;
    let channels = channels.as_array().unwrap();
    assert_eq!(channels.len(), 1);
    assert_eq!(channels[0]["name"], "general");
    let channel_id = channels[0]["id"].as_str().unwrap().to_owned();

    // And can send into it end to end, which is the flow a fresh deployment
    // could not do before bootstrap existed.
    let sent = app
        .clone()
        .oneshot(request(
            "POST",
            &format!("/channels/{channel_id}/messages"),
            Some(&admin),
            Some(json!({ "id": Uuid::now_v7().to_string(), "content": "first post" })),
        ))
        .await
        .unwrap();
    assert_eq!(sent.status(), StatusCode::OK);
    assert_eq!(json_body(sent).await["seq"], 1);

    // A second account joins on an invite, inherits @everyone, and can also
    // read and send.
    let member = join(&app, &admin, "bob").await;
    let listed = json_body(
        app.clone()
            .oneshot(request(
                "GET",
                &format!("/channels/{channel_id}/messages"),
                Some(&member),
                None,
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(listed.as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn bootstrap_runs_only_once() {
    let store = new_store().await;
    let first = store.create_user("alice", "Alice").await.unwrap();
    let second = store.create_user("bob", "Bob").await.unwrap();

    assert_eq!(
        store.bootstrap_deployment(first.id).await.unwrap(),
        Bootstrap::Claimed
    );
    // A second attempt changes nothing, so a later registration cannot seed a
    // competing set of roles or grant itself admin.
    assert_eq!(
        store.bootstrap_deployment(second.id).await.unwrap(),
        Bootstrap::AlreadySetUp
    );
    assert_eq!(store.list_channels().await.unwrap().len(), 1);
}

#[tokio::test]
async fn only_a_manager_can_create_channels() {
    let store = new_store().await;
    let app = app(store);
    let admin = register(&app, "alice").await;
    let member = join(&app, &admin, "bob").await;

    // The bootstrap admin can create one.
    let created = app
        .clone()
        .oneshot(request(
            "POST",
            "/channels",
            Some(&admin),
            Some(json!({ "name": "gaming" })),
        ))
        .await
        .unwrap();
    assert_eq!(created.status(), StatusCode::OK);
    assert_eq!(json_body(created).await["name"], "gaming");

    // An ordinary member cannot.
    let refused = app
        .clone()
        .oneshot(request(
            "POST",
            "/channels",
            Some(&member),
            Some(json!({ "name": "sneaky" })),
        ))
        .await
        .unwrap();
    assert_eq!(refused.status(), StatusCode::FORBIDDEN);

    // Validation still applies to the admin.
    let bad = app
        .clone()
        .oneshot(request(
            "POST",
            "/channels",
            Some(&admin),
            Some(json!({ "name": "  " })),
        ))
        .await
        .unwrap();
    assert_eq!(bad.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn channel_list_requires_authentication() {
    let store = new_store().await;
    let app = app(store);
    let response = app
        .oneshot(request("GET", "/channels", None, None))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

/// The password class refuses a caller past its burst, so a flood cannot keep
/// the Argon2id permits saturated.
#[tokio::test]
async fn password_endpoints_are_rate_limited() {
    let store = new_store().await;
    let app = app(store);

    let mut statuses = Vec::new();
    for i in 0..8 {
        let response = app
            .clone()
            .oneshot(request(
                "POST",
                "/auth/login",
                None,
                Some(json!({
                    "username": format!("nobody{i}"),
                    "password": "hunter2hunter2",
                    "device_name": "cli"
                })),
            ))
            .await
            .unwrap();
        statuses.push(response.status());
    }

    // The early attempts are answered normally (401, no such user); once the
    // burst is spent the limiter takes over.
    assert!(
        statuses.contains(&StatusCode::UNAUTHORIZED),
        "early attempts are answered: {statuses:?}"
    );
    assert!(
        statuses.contains(&StatusCode::TOO_MANY_REQUESTS),
        "a sustained flood is refused: {statuses:?}"
    );
}
