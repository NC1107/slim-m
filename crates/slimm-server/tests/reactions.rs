// SPDX-License-Identifier: AGPL-3.0-only
//! Reactions: idempotency, the permission gate, and the fact that reacting
//! cannot be used to discover a message in a channel you cannot read.

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
    let path = format!("/tmp/slimm-reactions-{}.db", Uuid::now_v7());
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

async fn register(app: &Router, username: &str) -> String {
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
                "device_name": "test"
            })),
        ))
        .await
        .unwrap();
    json_body(response).await["access_token"]
        .as_str()
        .unwrap()
        .to_owned()
}

/// Reacting twice with the same emoji must leave one reaction, because a double
/// tap on a slow connection is the normal case rather than an edge case.
#[tokio::test]
async fn reacting_twice_is_idempotent() {
    let store = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL
                .union(Permissions::SEND_MESSAGES)
                .union(Permissions::ADD_REACTIONS),
            true,
        )
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&app, "alice").await;

    let message_id = Uuid::now_v7().to_string();
    app.clone()
        .oneshot(request(
            "POST",
            &format!("/channels/{}/messages", channel.id),
            Some(&token),
            Some(json!({ "id": message_id, "content": "react to me" })),
        ))
        .await
        .unwrap();

    let uri = format!("/messages/{message_id}/reactions/%F0%9F%91%8D");
    for _ in 0..3 {
        let response = app
            .clone()
            .oneshot(request("PUT", &uri, Some(&token), None))
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
    let reactions = &listed.as_array().unwrap()[0]["reactions"];
    assert_eq!(reactions.as_array().unwrap().len(), 1);
    assert_eq!(reactions[0]["count"], 1, "three taps must count once");
    assert_eq!(reactions[0]["reacted"], true);

    // And removing is idempotent in the same way.
    for _ in 0..2 {
        let response = app
            .clone()
            .oneshot(request("DELETE", &uri, Some(&token), None))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::NO_CONTENT);
    }
}

/// Reacting must not confirm that a message exists in a channel the caller
/// cannot see: an unreadable message and a missing one answer identically.
#[tokio::test]
async fn reacting_cannot_probe_for_messages_you_cannot_see() {
    let store = new_store().await;
    // @everyone can send and react but NOT view, so the author can post
    // through a role of their own while a stranger sees nothing.
    store
        .create_role("everyone", Permissions::ADD_REACTIONS, true)
        .await
        .unwrap();
    let channel = store.create_channel("private", "text").await.unwrap();
    let app = app(store.clone());

    let stranger = register(&app, "stranger").await;

    // A message id that certainly does not exist.
    let missing = Uuid::now_v7().to_string();
    let missing_status = app
        .clone()
        .oneshot(request(
            "PUT",
            &format!("/messages/{missing}/reactions/%F0%9F%91%8D"),
            Some(&stranger),
            None,
        ))
        .await
        .unwrap()
        .status();

    // A real message in a channel the stranger cannot view.
    let author = store.create_user("author", "Author").await.unwrap();
    let real = slimm_server::ids::MessageId::generate();
    store
        .send_message(channel.id, author.id, real, "secret")
        .await
        .unwrap();
    let hidden_status = app
        .clone()
        .oneshot(request(
            "PUT",
            &format!("/messages/{real}/reactions/%F0%9F%91%8D"),
            Some(&stranger),
            None,
        ))
        .await
        .unwrap()
        .status();

    assert_eq!(missing_status, StatusCode::NOT_FOUND);
    assert_eq!(
        hidden_status, missing_status,
        "a hidden message must answer exactly as a missing one, or reacting is a probe"
    );
}
