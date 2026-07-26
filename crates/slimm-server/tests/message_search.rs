// SPDX-License-Identifier: AGPL-3.0-only
//! Full-text message search: matching, permission scoping, deleted-message
//! exclusion, and malformed FTS5 syntax answering 400 rather than 500.

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
        .join(format!("slimm-message-search-{}.db", Uuid::now_v7()))
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

/// A member with a session, built straight through the store.
///
/// Deliberately not the `/auth/register` route: joining a claimed deployment
/// is an invite-gated policy decision, and it is pinned by its own tests in
/// `registration_gate.rs`. These tests only need somebody signed in, so going
/// through the store keeps them independent of that policy.
async fn register(store: &Store, username: &str) -> String {
    let account = store
        .create_account(username, username, "not-a-real-hash")
        .await
        .unwrap();
    // The first account through here claims the deployment, exactly as the
    // first real registration does; later ones find it already set up.
    store.bootstrap_deployment(account.id).await.unwrap();
    store
        .open_session(account.id, "cli")
        .await
        .unwrap()
        .access_token
}

async fn send(app: &Router, channel_id: &str, token: &str, content: &str) -> Value {
    json_body(
        app.clone()
            .oneshot(request(
                "POST",
                &format!("/channels/{channel_id}/messages"),
                Some(token),
                Some(json!({ "id": Uuid::now_v7().to_string(), "content": content })),
            ))
            .await
            .unwrap(),
    )
    .await
}

/// A search returns only the messages whose content matches, not everything
/// in the channel.
#[tokio::test]
async fn search_returns_matching_messages_only() {
    let store = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES),
            true,
        )
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;
    let channel_id = channel.id.to_string();

    send(&app, &channel_id, &token, "the quick brown fox").await;
    send(&app, &channel_id, &token, "a slow red turtle").await;

    let results = json_body(
        app.clone()
            .oneshot(request(
                "GET",
                &format!("/channels/{channel_id}/messages/search?q=fox"),
                Some(&token),
                None,
            ))
            .await
            .unwrap(),
    )
    .await;
    let results = results.as_array().unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0]["content"], "the quick brown fox");
}

/// A deleted message is not returned by search, even though the FTS index
/// still technically carries it until touched again.
#[tokio::test]
async fn search_excludes_deleted_messages() {
    let store = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES),
            true,
        )
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;
    let channel_id = channel.id.to_string();

    let sent = send(&app, &channel_id, &token, "unicorns are searchable").await;
    let message_id = sent["id"].as_str().unwrap();

    app.clone()
        .oneshot(request(
            "DELETE",
            &format!("/channels/{channel_id}/messages/{message_id}"),
            Some(&token),
            None,
        ))
        .await
        .unwrap();

    let results = json_body(
        app.clone()
            .oneshot(request(
                "GET",
                &format!("/channels/{channel_id}/messages/search?q=unicorns"),
                Some(&token),
                None,
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(results.as_array().unwrap().len(), 0);
}

/// Searching a channel the caller cannot view is refused exactly like
/// listing it would be, so it cannot be used to probe for a hidden channel.
#[tokio::test]
async fn search_requires_view_permission() {
    let store = new_store().await;
    store
        .create_role("everyone", Permissions::NONE, true)
        .await
        .unwrap();
    let channel = store.create_channel("private", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "GET",
            &format!("/channels/{}/messages/search?q=anything", channel.id),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

/// Malformed FTS5 query syntax is a clean 400, never a 500.
#[tokio::test]
async fn a_malformed_query_is_a_bad_request_not_a_server_error() {
    let store = new_store().await;
    store
        .create_role("everyone", Permissions::VIEW_CHANNEL, true)
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    // A dangling boolean operator is not valid FTS5 syntax.
    let response = app
        .clone()
        .oneshot(request(
            "GET",
            &format!("/channels/{}/messages/search?q=hello%20AND", channel.id),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

/// An empty query is rejected before ever reaching FTS5.
#[tokio::test]
async fn an_empty_query_is_rejected() {
    let store = new_store().await;
    store
        .create_role("everyone", Permissions::VIEW_CHANNEL, true)
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "GET",
            &format!("/channels/{}/messages/search?q=%20%20", channel.id),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

/// A search cannot be crafted to pull results from a different channel: the
/// channel restriction is a separate SQL predicate the query text never
/// reaches, so it stays scoped no matter what FTS5 syntax `q` uses.
#[tokio::test]
async fn search_stays_scoped_to_its_own_channel() {
    let store = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES),
            true,
        )
        .await
        .unwrap();
    let channel_a = store.create_channel("a", "text").await.unwrap();
    let channel_b = store.create_channel("b", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    send(
        &app,
        &channel_a.id.to_string(),
        &token,
        "alpha secret words",
    )
    .await;
    send(
        &app,
        &channel_b.id.to_string(),
        &token,
        "alpha secret words",
    )
    .await;

    let results = json_body(
        app.clone()
            .oneshot(request(
                "GET",
                &format!(
                    "/channels/{}/messages/search?q=alpha%20OR%20secret",
                    channel_a.id
                ),
                Some(&token),
                None,
            ))
            .await
            .unwrap(),
    )
    .await;
    let results = results.as_array().unwrap();
    assert_eq!(
        results.len(),
        1,
        "only channel A's own message should match"
    );
    assert_eq!(results[0]["channel_id"], channel_a.id.to_string());
}
