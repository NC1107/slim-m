// SPDX-License-Identifier: AGPL-3.0-only
//! HTTP integration tests for read state and the bundled sync endpoint.

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::ids::{MessageId, UserId};
use slimm_server::permissions::Permissions;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use tower::ServiceExt;

async fn new_store() -> Store {
    let path = format!("/tmp/slimm-sync-test-{}.db", uuid::Uuid::now_v7());
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    Store::new(pool)
}

/// A user, their access token, and a router sharing the store.
struct Fixture {
    store: Store,
    app: Router,
    user_id: UserId,
    token: String,
}

async fn setup(everyone: Permissions) -> Fixture {
    let store = new_store().await;
    store.create_role("everyone", everyone, true).await.unwrap();
    let app = http::router(AppState {
        store: store.clone(),
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
    });
    let user = store.create_user("alice", "Alice").await.unwrap();
    let tokens = store.open_session(user.id, "dev").await.unwrap();
    Fixture {
        store,
        app,
        user_id: user.id,
        token: tokens.access_token,
    }
}

fn request(method: &str, uri: &str, token: &str, body: Option<Value>) -> Request<Body> {
    let builder = Request::builder()
        .method(method)
        .uri(uri)
        .header("authorization", format!("Bearer {token}"));
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

#[tokio::test]
async fn read_state_tracks_unread_and_is_monotonic() {
    let f = setup(Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES)).await;
    let channel = f.store.create_channel("general", "text").await.unwrap();
    for i in 0..3 {
        f.store
            .send_message(
                channel.id,
                f.user_id,
                MessageId::generate(),
                &format!("m{i}"),
            )
            .await
            .unwrap();
    }
    let read_uri = format!("/channels/{}/read", channel.id);

    // Nothing read yet: three unread.
    let body = json_body(
        f.app
            .clone()
            .oneshot(request("GET", &read_uri, &f.token, None))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(body["last_read_seq"], 0);
    assert_eq!(body["unread"], 3);

    // Mark up to seq 2: one unread remains.
    let body = json_body(
        f.app
            .clone()
            .oneshot(request(
                "PUT",
                &read_uri,
                &f.token,
                Some(json!({ "seq": 2 })),
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(body["last_read_seq"], 2);
    assert_eq!(body["unread"], 1);

    // A lower seq does not move the marker backwards.
    let body = json_body(
        f.app
            .clone()
            .oneshot(request(
                "PUT",
                &read_uri,
                &f.token,
                Some(json!({ "seq": 1 })),
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(body["last_read_seq"], 2);
    assert_eq!(body["unread"], 1);

    // Catching up to the latest clears unread.
    let body = json_body(
        f.app
            .clone()
            .oneshot(request(
                "PUT",
                &read_uri,
                &f.token,
                Some(json!({ "seq": 3 })),
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(body["last_read_seq"], 3);
    assert_eq!(body["unread"], 0);
}

#[tokio::test]
async fn read_state_requires_view() {
    let f = setup(Permissions::NONE).await;
    let channel = f.store.create_channel("general", "text").await.unwrap();
    let response = f
        .app
        .clone()
        .oneshot(request(
            "GET",
            &format!("/channels/{}/read", channel.id),
            &f.token,
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn sync_returns_messages_after_the_cursor() {
    let f = setup(Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES)).await;
    let channel = f.store.create_channel("general", "text").await.unwrap();
    for i in 0..5 {
        f.store
            .send_message(
                channel.id,
                f.user_id,
                MessageId::generate(),
                &format!("m{i}"),
            )
            .await
            .unwrap();
    }

    // Everything after seq 2 is 3, 4, 5.
    let body = json_body(
        f.app
            .clone()
            .oneshot(request(
                "POST",
                "/sync",
                &f.token,
                Some(
                    json!({ "scopes": [{ "channel_id": channel.id.to_string(), "after_seq": 2 }] }),
                ),
            ))
            .await
            .unwrap(),
    )
    .await;
    let scope = &body["scopes"][0];
    assert_eq!(scope["has_more"], false);
    assert_eq!(scope["reset"], false);
    let messages = scope["messages"].as_array().unwrap();
    assert_eq!(messages.len(), 3);
    assert_eq!(messages[0]["seq"], 3);
    assert_eq!(messages[2]["seq"], 5);

    // Caught up: nothing new.
    let body = json_body(
        f.app
            .clone()
            .oneshot(request(
                "POST",
                "/sync",
                &f.token,
                Some(
                    json!({ "scopes": [{ "channel_id": channel.id.to_string(), "after_seq": 5 }] }),
                ),
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(body["scopes"][0]["messages"].as_array().unwrap().len(), 0);
    assert_eq!(body["scopes"][0]["has_more"], false);
}

#[tokio::test]
async fn sync_skips_channels_without_view() {
    let f = setup(Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES)).await;
    let visible = f.store.create_channel("visible", "text").await.unwrap();
    let hidden = f.store.create_channel("hidden", "text").await.unwrap();
    f.store
        .send_message(visible.id, f.user_id, MessageId::generate(), "hi")
        .await
        .unwrap();
    f.store
        .send_message(hidden.id, f.user_id, MessageId::generate(), "secret")
        .await
        .unwrap();
    // Deny alice the view of the hidden channel.
    f.store
        .set_member_overwrite(
            hidden.id,
            f.user_id,
            Permissions::NONE,
            Permissions::VIEW_CHANNEL,
        )
        .await
        .unwrap();

    let body = json_body(
        f.app
            .clone()
            .oneshot(request(
                "POST",
                "/sync",
                &f.token,
                Some(json!({ "scopes": [
                    { "channel_id": visible.id.to_string(), "after_seq": 0 },
                    { "channel_id": hidden.id.to_string(), "after_seq": 0 }
                ] })),
            ))
            .await
            .unwrap(),
    )
    .await;
    // Only the visible channel comes back; the hidden one is omitted entirely.
    let scopes = body["scopes"].as_array().unwrap();
    assert_eq!(scopes.len(), 1);
    assert_eq!(scopes[0]["channel_id"], visible.id.to_string());
}

#[tokio::test]
async fn a_nonexistent_channel_is_hidden_like_a_denied_one() {
    let f = setup(Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES)).await;
    let fake = uuid::Uuid::now_v7().to_string();

    // GET read on a fabricated id is refused, not answered with an empty state,
    // so it cannot be told apart from a channel the caller may not view.
    let response = f
        .app
        .clone()
        .oneshot(request(
            "GET",
            &format!("/channels/{fake}/read"),
            &f.token,
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    // sync omits the fabricated scope entirely.
    let body = json_body(
        f.app
            .clone()
            .oneshot(request(
                "POST",
                "/sync",
                &f.token,
                Some(json!({ "scopes": [{ "channel_id": fake, "after_seq": 0 }] })),
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(body["scopes"].as_array().unwrap().len(), 0);
}

#[tokio::test]
async fn sync_collapses_duplicate_scopes() {
    let f = setup(Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES)).await;
    let channel = f.store.create_channel("general", "text").await.unwrap();
    for i in 0..5 {
        f.store
            .send_message(
                channel.id,
                f.user_id,
                MessageId::generate(),
                &format!("m{i}"),
            )
            .await
            .unwrap();
    }

    // The same channel twice, with different cursors, collapses to one scope
    // that honors the smallest after_seq (the most it could ask for).
    let body = json_body(
        f.app
            .clone()
            .oneshot(request(
                "POST",
                "/sync",
                &f.token,
                Some(json!({ "scopes": [
                    { "channel_id": channel.id.to_string(), "after_seq": 4 },
                    { "channel_id": channel.id.to_string(), "after_seq": 0 }
                ] })),
            ))
            .await
            .unwrap(),
    )
    .await;
    let scopes = body["scopes"].as_array().unwrap();
    assert_eq!(scopes.len(), 1);
    assert_eq!(scopes[0]["messages"].as_array().unwrap().len(), 5);
}

#[tokio::test]
async fn sync_far_behind_cursor_asks_for_reset() {
    let f = setup(Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES)).await;
    let channel = f.store.create_channel("general", "text").await.unwrap();
    f.store
        .send_message(channel.id, f.user_id, MessageId::generate(), "hi")
        .await
        .unwrap();

    // A cursor implausibly far behind latest gets a reset, not a huge backlog.
    let body = json_body(
        f.app
            .clone()
            .oneshot(request(
                "POST",
                "/sync",
                &f.token,
                Some(json!({ "scopes": [{ "channel_id": channel.id.to_string(), "after_seq": -5000 }] })),
            ))
            .await
            .unwrap(),
    )
    .await;
    let scope = &body["scopes"][0];
    assert_eq!(scope["reset"], true);
    assert_eq!(scope["messages"].as_array().unwrap().len(), 0);
}
