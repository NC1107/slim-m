// SPDX-License-Identifier: AGPL-3.0-only
//! Message deletion: author-or-manage authorization, idempotency, and the
//! fact that it cannot be used to probe for a message in a channel the
//! caller cannot see.

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
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use tower::ServiceExt;
use uuid::Uuid;

async fn new_store() -> Store {
    let path = std::env::temp_dir()
        .join(format!("slimm-message-delete-{}.db", Uuid::now_v7()))
        .to_string_lossy()
        .into_owned();
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
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

/// The author can delete their own message, and a second delete of the same
/// message is not an error: it must stay idempotent for a client retrying
/// after a dropped response.
#[tokio::test]
async fn author_can_delete_their_own_message_and_it_is_idempotent() {
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
    let (token, _user) = register(&store, "alice").await;

    let sent = send(&app, &channel.id.to_string(), &token, "delete me").await;
    let message_id = sent["id"].as_str().unwrap().to_owned();
    let uri = format!("/channels/{}/messages/{message_id}", channel.id);

    for _ in 0..2 {
        let response = app
            .clone()
            .oneshot(request("DELETE", &uri, Some(&token), None))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::NO_CONTENT);
    }

    let listed = json_body(
        app.clone()
            .oneshot(request(
                "GET",
                &format!("/channels/{}/messages", channel.id),
                Some(&token),
                None,
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(
        listed.as_array().unwrap().len(),
        0,
        "a deleted message must not appear in history"
    );
}

/// An ordinary member cannot delete someone else's message; a member with
/// MANAGE_MESSAGES can.
#[tokio::test]
async fn deleting_anothers_message_needs_manage_messages() {
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

    let (alice_token, _alice) = register(&store, "alice").await;
    let (bob_token, bob_id) = register(&store, "bob").await;

    let sent = send(
        &app,
        &channel.id.to_string(),
        &alice_token,
        "alice's message",
    )
    .await;
    let message_id = sent["id"].as_str().unwrap().to_owned();
    let uri = format!("/channels/{}/messages/{message_id}", channel.id);

    let forbidden = app
        .clone()
        .oneshot(request("DELETE", &uri, Some(&bob_token), None))
        .await
        .unwrap();
    assert_eq!(forbidden.status(), StatusCode::FORBIDDEN);

    let bob = UserId(Uuid::parse_str(&bob_id).unwrap());
    store.assign_role(bob, mods).await.unwrap();
    let allowed = app
        .clone()
        .oneshot(request("DELETE", &uri, Some(&bob_token), None))
        .await
        .unwrap();
    assert_eq!(allowed.status(), StatusCode::NO_CONTENT);
}

/// Deleting a message in a channel the caller cannot view must answer exactly
/// as deleting a nonexistent message would, so the endpoint cannot be used to
/// probe for messages in a hidden channel.
#[tokio::test]
async fn deleting_in_a_hidden_channel_cannot_be_used_to_probe() {
    let store = new_store().await;
    store
        .create_role("everyone", Permissions::NONE, true)
        .await
        .unwrap();
    let channel = store.create_channel("private", "text").await.unwrap();
    let app = app(store.clone());
    let (token, _user) = register(&store, "alice").await;

    let real = slimm_server::ids::MessageId::generate();
    let author = store.create_user("author", "Author").await.unwrap();
    store
        .send_message(channel.id, author.id, real, "secret", &[])
        .await
        .unwrap();

    let hidden = app
        .clone()
        .oneshot(request(
            "DELETE",
            &format!("/channels/{}/messages/{real}", channel.id),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(hidden.status(), StatusCode::FORBIDDEN);
}

/// Deleting a message id that never existed, in a channel the caller can
/// view, is a plain 404.
#[tokio::test]
async fn deleting_an_unknown_message_in_a_visible_channel_is_not_found() {
    let store = new_store().await;
    store
        .create_role("everyone", Permissions::VIEW_CHANNEL, true)
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let app = app(store.clone());
    let (token, _user) = register(&store, "alice").await;

    let missing = Uuid::now_v7();
    let response = app
        .clone()
        .oneshot(request(
            "DELETE",
            &format!("/channels/{}/messages/{missing}", channel.id),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}
