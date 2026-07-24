// SPDX-License-Identifier: AGPL-3.0-only
//! HTTP integration tests for the message endpoints, covering the happy path,
//! idempotency, validation, and the authorization matrix.

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::ids::UserId;
use slimm_server::permissions::Permissions;
use slimm_server::store::Store;
use tower::ServiceExt;
use uuid::Uuid;

async fn new_store() -> Store {
    let path = format!("/tmp/slimm-msg-test-{}.db", uuid::Uuid::now_v7());
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    Store::new(pool)
}

/// Builds a router sharing `store`, so roles and channels created directly on the
/// store are visible to the handlers.
fn app(store: Store) -> Router {
    let auth = Auth::new(2).expect("auth service");
    http::router(AppState {
        store,
        auth,
        hub: Hub::new(),
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

/// Registers a user and returns (access_token, user_id).
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
    assert_eq!(response.status(), StatusCode::OK);
    let body = json_body(response).await;
    (
        body["access_token"].as_str().unwrap().to_owned(),
        body["user_id"].as_str().unwrap().to_owned(),
    )
}

#[tokio::test]
async fn send_list_and_edit_happy_path() {
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
    let app = app(store);
    let (token, _user) = register(&app, "alice").await;

    let uri = format!("/channels/{}/messages", channel.id);
    let message_id = Uuid::now_v7().to_string();

    // Send.
    let sent = app
        .clone()
        .oneshot(request(
            "POST",
            &uri,
            Some(&token),
            Some(json!({ "id": message_id, "content": "hello" })),
        ))
        .await
        .unwrap();
    assert_eq!(sent.status(), StatusCode::OK);
    let sent = json_body(sent).await;
    assert_eq!(sent["seq"], 1);
    assert_eq!(sent["content"], "hello");

    // List returns it.
    let listed = app
        .clone()
        .oneshot(request("GET", &uri, Some(&token), None))
        .await
        .unwrap();
    assert_eq!(listed.status(), StatusCode::OK);
    let listed = json_body(listed).await;
    assert_eq!(listed.as_array().unwrap().len(), 1);
    assert_eq!(listed[0]["id"], message_id);

    // Edit own message.
    let edit_uri = format!("/channels/{}/messages/{}", channel.id, message_id);
    let edited = app
        .clone()
        .oneshot(request(
            "PATCH",
            &edit_uri,
            Some(&token),
            Some(json!({ "content": "hello again" })),
        ))
        .await
        .unwrap();
    assert_eq!(edited.status(), StatusCode::OK);
    let edited = json_body(edited).await;
    assert_eq!(edited["content"], "hello again");
    assert!(edited["edited_at"].is_i64());
}

#[tokio::test]
async fn send_is_idempotent_over_http() {
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
    let app = app(store);
    let (token, _user) = register(&app, "alice").await;

    let uri = format!("/channels/{}/messages", channel.id);
    let message_id = Uuid::now_v7().to_string();
    let send = |content: &str| {
        request(
            "POST",
            &uri,
            Some(&token),
            Some(json!({ "id": message_id, "content": content })),
        )
    };

    let first = json_body(app.clone().oneshot(send("original")).await.unwrap()).await;
    // A retry with the same id returns the stored message, not the new content.
    let retry = json_body(app.clone().oneshot(send("changed")).await.unwrap()).await;
    assert_eq!(first["seq"], retry["seq"]);
    assert_eq!(retry["content"], "original");

    let listed = json_body(
        app.clone()
            .oneshot(request("GET", &uri, Some(&token), None))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(listed.as_array().unwrap().len(), 1, "no duplicate row");
}

#[tokio::test]
async fn send_id_is_scoped_to_channel_and_author() {
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
    let app = app(store);
    let (alice, _alice_id) = register(&app, "alice").await;
    let (bob, _bob_id) = register(&app, "bob").await;

    let shared_id = Uuid::now_v7().to_string();

    // Alice posts the id into channel A.
    let sent = app
        .clone()
        .oneshot(request(
            "POST",
            &format!("/channels/{}/messages", channel_a.id),
            Some(&alice),
            Some(json!({ "id": shared_id, "content": "alice in A" })),
        ))
        .await
        .unwrap();
    assert_eq!(sent.status(), StatusCode::OK);

    // Reusing the same id in a different channel is a conflict; it must never
    // return channel A's message (the IDOR this guards against).
    let cross_channel = app
        .clone()
        .oneshot(request(
            "POST",
            &format!("/channels/{}/messages", channel_b.id),
            Some(&alice),
            Some(json!({ "id": shared_id, "content": "alice in B" })),
        ))
        .await
        .unwrap();
    assert_eq!(cross_channel.status(), StatusCode::CONFLICT);

    // Another author reusing the id in the same channel is also a conflict.
    let cross_author = app
        .clone()
        .oneshot(request(
            "POST",
            &format!("/channels/{}/messages", channel_a.id),
            Some(&bob),
            Some(json!({ "id": shared_id, "content": "bob in A" })),
        ))
        .await
        .unwrap();
    assert_eq!(cross_author.status(), StatusCode::CONFLICT);
}

#[tokio::test]
async fn permissions_are_enforced() {
    // @everyone can view but not send.
    let store = new_store().await;
    store
        .create_role("everyone", Permissions::VIEW_CHANNEL, true)
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let app = app(store);
    let (token, _user) = register(&app, "alice").await;

    let uri = format!("/channels/{}/messages", channel.id);

    // View is allowed.
    let listed = app
        .clone()
        .oneshot(request("GET", &uri, Some(&token), None))
        .await
        .unwrap();
    assert_eq!(listed.status(), StatusCode::OK);

    // Sending is forbidden.
    let sent = app
        .clone()
        .oneshot(request(
            "POST",
            &uri,
            Some(&token),
            Some(json!({ "id": Uuid::now_v7().to_string(), "content": "nope" })),
        ))
        .await
        .unwrap();
    assert_eq!(sent.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn no_view_permission_hides_the_channel() {
    let store = new_store().await;
    store
        .create_role("everyone", Permissions::NONE, true)
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let app = app(store);
    let (token, _user) = register(&app, "alice").await;

    let listed = app
        .clone()
        .oneshot(request(
            "GET",
            &format!("/channels/{}/messages", channel.id),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(listed.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn editing_another_users_message_needs_manage() {
    let store = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES),
            true,
        )
        .await
        .unwrap();
    let mods = store
        .create_role("mods", Permissions::MANAGE_MESSAGES, false)
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let app = app(store.clone());

    let (alice_token, _alice) = register(&app, "alice").await;
    let (bob_token, bob_id) = register(&app, "bob").await;

    // Alice sends a message.
    let uri = format!("/channels/{}/messages", channel.id);
    let message_id = Uuid::now_v7().to_string();
    let sent = app
        .clone()
        .oneshot(request(
            "POST",
            &uri,
            Some(&alice_token),
            Some(json!({ "id": message_id, "content": "alice's message" })),
        ))
        .await
        .unwrap();
    assert_eq!(sent.status(), StatusCode::OK);

    let edit_uri = format!("/channels/{}/messages/{}", channel.id, message_id);
    let edit = |token: &str| {
        request(
            "PATCH",
            &edit_uri,
            Some(token),
            Some(json!({ "content": "edited by bob" })),
        )
    };

    // Bob, an ordinary member, cannot edit Alice's message.
    let forbidden = app.clone().oneshot(edit(&bob_token)).await.unwrap();
    assert_eq!(forbidden.status(), StatusCode::FORBIDDEN);

    // Give Bob the mods role; now he can.
    let bob = UserId(Uuid::parse_str(&bob_id).unwrap());
    store.assign_role(bob, mods).await.unwrap();
    let allowed = app.clone().oneshot(edit(&bob_token)).await.unwrap();
    assert_eq!(allowed.status(), StatusCode::OK);
}

#[tokio::test]
async fn validation_and_missing_resources() {
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
    let app = app(store);
    let (token, _user) = register(&app, "alice").await;

    let uri = format!("/channels/{}/messages", channel.id);

    // Empty content is a 400.
    let empty = app
        .clone()
        .oneshot(request(
            "POST",
            &uri,
            Some(&token),
            Some(json!({ "id": Uuid::now_v7().to_string(), "content": "   " })),
        ))
        .await
        .unwrap();
    assert_eq!(empty.status(), StatusCode::BAD_REQUEST);

    // Posting to a channel that does not exist is refused the same way as one
    // the caller cannot see (a nonexistent channel grants no permissions), so it
    // reveals nothing about whether the channel is real.
    let missing = app
        .clone()
        .oneshot(request(
            "POST",
            &format!("/channels/{}/messages", Uuid::now_v7()),
            Some(&token),
            Some(json!({ "id": Uuid::now_v7().to_string(), "content": "hi" })),
        ))
        .await
        .unwrap();
    assert_eq!(missing.status(), StatusCode::FORBIDDEN);

    // No bearer token is a 401.
    let anon = app
        .clone()
        .oneshot(request("GET", &uri, None, None))
        .await
        .unwrap();
    assert_eq!(anon.status(), StatusCode::UNAUTHORIZED);
}
