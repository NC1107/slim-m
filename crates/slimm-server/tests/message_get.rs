// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! `GET /channels/{channel_id}/messages/{message_id}`: enrichment parity
//! with `listMessages`, and the uniform 404 that keeps it from being a
//! channel-existence oracle for a caller naming one specific id.

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

mod support;

async fn new_store(name: &str) -> (Store, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new(name);
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
        gifs: slimm_server::http::gifs::GifSearch::disabled(),
        link_previews: slimm_server::http::link_preview::LinkPreviews::disabled(),
        dock: slimm_server::http::dock::Dock::disabled(),
        code_runner: slimm_server::code_runner::CodeRunner::disabled(),
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
    serde_json::from_slice(&bytes).unwrap_or(Value::Null)
}

/// A member with a session, built straight through the store - joining a
/// claimed deployment is its own policy, pinned by `registration_gate.rs`.
async fn register(store: &Store, username: &str) -> String {
    let account = store
        .create_account(username, username, "not-a-real-hash")
        .await
        .unwrap();
    store.bootstrap_deployment(account.id).await.unwrap();
    store
        .open_session(account.id, "cli")
        .await
        .unwrap()
        .access_token
}

#[tokio::test]
async fn get_message_matches_list_enrichment() {
    let (store, _guard) = new_store("slimm-get-message-parity").await;
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
    let token = register(&store, "alice").await;

    let message_id = Uuid::now_v7().to_string();
    let send_uri = format!("/channels/{}/messages", channel.id);
    let sent = app
        .clone()
        .oneshot(request(
            "POST",
            &send_uri,
            Some(&token),
            Some(json!({ "id": message_id, "content": "hello" })),
        ))
        .await
        .unwrap();
    assert_eq!(sent.status(), StatusCode::OK);

    // React too, so there is real enrichment beyond the bare row to compare.
    let reacted = app
        .clone()
        .oneshot(request(
            "PUT",
            &format!("/messages/{message_id}/reactions/%F0%9F%91%8D"),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(reacted.status(), StatusCode::NO_CONTENT);

    let listed = json_body(
        app.clone()
            .oneshot(request("GET", &send_uri, Some(&token), None))
            .await
            .unwrap(),
    )
    .await;
    let list_entry = listed
        .as_array()
        .unwrap()
        .iter()
        .find(|m| m["id"] == message_id)
        .cloned()
        .expect("the sent message is in the list");
    assert!(
        !list_entry["reactions"].as_array().unwrap().is_empty(),
        "the fixture must actually carry a reaction, or this proves nothing"
    );

    let fetched = json_body(
        app.oneshot(request(
            "GET",
            &format!("/channels/{}/messages/{message_id}", channel.id),
            Some(&token),
            None,
        ))
        .await
        .unwrap(),
    )
    .await;

    assert_eq!(
        fetched, list_entry,
        "GET one message must carry exactly what list's enrichment does"
    );
}

#[tokio::test]
async fn a_channel_the_caller_cannot_view_answers_404_not_403() {
    let (store, _guard) = new_store("slimm-get-message-hides-channel").await;
    store
        .create_role("everyone", Permissions::NONE, true)
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    let response = app
        .oneshot(request(
            "GET",
            &format!("/channels/{}/messages/{}", channel.id, Uuid::now_v7()),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "a 403 here would confirm the channel exists to a caller who cannot see it"
    );
}

#[tokio::test]
async fn missing_channel_missing_message_and_no_permission_all_answer_the_identical_404() {
    let (store, _guard) = new_store("slimm-get-message-uniform-404").await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES),
            true,
        )
        .await
        .unwrap();
    let visible = store.create_channel("general", "text").await.unwrap();
    let visible_app = app(store.clone());
    let token = register(&store, "alice").await;

    let (store_hidden, _hidden_guard) = new_store("slimm-get-message-uniform-404-hidden").await;
    store_hidden
        .create_role("everyone", Permissions::NONE, true)
        .await
        .unwrap();
    let hidden_channel = store_hidden
        .create_channel("general", "text")
        .await
        .unwrap();
    let hidden_token = register(&store_hidden, "bob").await;
    let hidden_app = app(store_hidden.clone());

    let never_existed = visible_app
        .oneshot(request(
            "GET",
            &format!("/channels/{}/messages/{}", visible.id, Uuid::now_v7()),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    let unreachable_channel = hidden_app
        .oneshot(request(
            "GET",
            &format!(
                "/channels/{}/messages/{}",
                hidden_channel.id,
                Uuid::now_v7()
            ),
            Some(&hidden_token),
            None,
        ))
        .await
        .unwrap();

    assert_eq!(never_existed.status(), StatusCode::NOT_FOUND);
    assert_eq!(unreachable_channel.status(), StatusCode::NOT_FOUND);
    assert_eq!(
        json_body(never_existed).await,
        json_body(unreachable_channel).await,
        "a nonexistent message and a channel the caller cannot see must not be tellable apart"
    );
}
