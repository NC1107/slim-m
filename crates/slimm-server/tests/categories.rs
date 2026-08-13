// SPDX-License-Identifier: AGPL-3.0-only
//! Channel categories: the MANAGE_CHANNELS gate, create/rename/reposition,
//! and that deleting a category never deletes its channels. See
//! docs/decisions/0006-channel-categories.md.

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

mod support;

async fn new_store() -> (Store, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new("slimm-categories-test");
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
async fn manager_can_create_rename_and_reposition_a_category() {
    let (store, _guard) = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::MANAGE_CHANNELS),
            true,
        )
        .await
        .unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    let created = json_body(
        app.clone()
            .oneshot(request(
                "POST",
                "/categories",
                Some(&token),
                Some(json!({ "name": "extras" })),
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(created["name"], "extras");
    let category_id = created["id"].as_str().unwrap().to_owned();

    let updated = json_body(
        app.clone()
            .oneshot(request(
                "PATCH",
                &format!("/categories/{category_id}"),
                Some(&token),
                Some(json!({ "name": "renamed", "position": 5 })),
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(updated["name"], "renamed");
    assert_eq!(updated["position"].as_i64().unwrap(), 5);
}

#[tokio::test]
async fn creating_a_category_without_manage_channels_is_forbidden() {
    let (store, _guard) = new_store().await;
    store
        .create_role("everyone", Permissions::VIEW_CHANNEL, true)
        .await
        .unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "POST",
            "/categories",
            Some(&token),
            Some(json!({ "name": "extras" })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

/// An update naming neither field is a 400, the same convention
/// `updateChannel` follows.
#[tokio::test]
async fn updating_a_category_with_nothing_to_change_is_bad_request() {
    let (store, _guard) = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::MANAGE_CHANNELS),
            true,
        )
        .await
        .unwrap();
    let category = store.create_category("extras").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "PATCH",
            &format!("/categories/{}", category.id),
            Some(&token),
            Some(json!({})),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

/// Deleting a category never deletes the channels filed under it - they fall
/// back to uncategorised, the load-bearing property the decision record
/// names as the reason this cannot be a cascading foreign key.
#[tokio::test]
async fn deleting_a_category_keeps_its_channels_and_uncategorises_them() {
    let (store, _guard) = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::MANAGE_CHANNELS),
            true,
        )
        .await
        .unwrap();
    let category = store.create_category("extras").await.unwrap();
    let channel = store.create_channel("a", "text").await.unwrap();
    store
        .reorder_channels(&[slimm_server::store::ChannelOrderGroup {
            category_id: Some(category.id),
            channel_ids: vec![channel.id],
        }])
        .await
        .unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "DELETE",
            &format!("/categories/{}", category.id),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    let still_there = store
        .channel(channel.id)
        .await
        .unwrap()
        .expect("the channel must not have been deleted along with its category");
    assert_eq!(
        still_there.category_id, None,
        "an orphaned channel falls back to uncategorised"
    );

    // Idempotent: deleting it again is still a 204, not a 404.
    let again = app
        .oneshot(request(
            "DELETE",
            &format!("/categories/{}", category.id),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(again.status(), StatusCode::NO_CONTENT);
}

/// The last-channel delete guard is unaffected by category placement:
/// spreading channels across categories must not let a deployment be talked
/// down to zero live channels, since categories decide placement only.
#[tokio::test]
async fn the_last_channel_guard_is_unaffected_by_categories() {
    let (store, _guard) = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::MANAGE_CHANNELS),
            true,
        )
        .await
        .unwrap();
    let voice_cat = store.create_category("Voice").await.unwrap();
    let a = store.create_channel("a", "text").await.unwrap();
    let b = store.create_channel("b", "voice").await.unwrap();
    store
        .reorder_channels(&[
            slimm_server::store::ChannelOrderGroup {
                category_id: None,
                channel_ids: vec![a.id],
            },
            slimm_server::store::ChannelOrderGroup {
                category_id: Some(voice_cat.id),
                channel_ids: vec![b.id],
            },
        ])
        .await
        .unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    let first = app
        .clone()
        .oneshot(request(
            "DELETE",
            &format!("/channels/{}", a.id),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(first.status(), StatusCode::NO_CONTENT);

    let refused = app
        .oneshot(request(
            "DELETE",
            &format!("/channels/{}", b.id),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(
        refused.status(),
        StatusCode::CONFLICT,
        "the last live channel is refused however its category is arranged"
    );
}
