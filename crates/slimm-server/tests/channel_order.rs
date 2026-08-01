// SPDX-License-Identifier: AGPL-3.0-only
//! `PUT /channels/order`: the MANAGE_CHANNELS gate, the all-or-nothing
//! validation that names exactly the live non-DM channels, the position
//! this actually writes, and the no-op case that changes nothing.

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

async fn new_store() -> (Store, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new("slimm-channel-order-test");
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

/// A member with a session, built straight through the store. See
/// `tests/channels.rs`'s own copy of this for why it bypasses `/auth/register`.
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

fn ids(listed: &Value) -> Vec<String> {
    listed
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["id"].as_str().unwrap().to_owned())
        .collect()
}

#[tokio::test]
async fn manager_can_reorder_channels() {
    let (store, _guard) = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::MANAGE_CHANNELS),
            true,
        )
        .await
        .unwrap();
    let a = store.create_channel("a", "text").await.unwrap();
    let b = store.create_channel("b", "text").await.unwrap();
    let c = store.create_channel("c", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    let new_order = vec![c.id.to_string(), a.id.to_string(), b.id.to_string()];
    let response = app
        .clone()
        .oneshot(request(
            "PUT",
            "/channels/order",
            Some(&token),
            Some(json!({ "channel_ids": new_order.clone() })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = json_body(response).await;
    assert_eq!(ids(&body), new_order);
    let positions: Vec<i64> = body
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["position"].as_i64().unwrap())
        .collect();
    assert_eq!(positions, vec![0, 1, 2]);

    // Persisted, not just echoed back.
    let listed = json_body(
        app.clone()
            .oneshot(request("GET", "/channels", Some(&token), None))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(ids(&listed), new_order);
}

/// A freshly created channel always lands at the end of the order, not at
/// position 0: `create_channel` has to read the live maximum in the same
/// transaction, or a new channel would collide with (and sort before, on the
/// `created_at` tiebreak) whichever channel already held position 0.
#[tokio::test]
async fn a_new_channel_is_appended_after_a_reorder_has_run() {
    let (store, _guard) = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::MANAGE_CHANNELS),
            true,
        )
        .await
        .unwrap();
    let a = store.create_channel("a", "text").await.unwrap();
    let b = store.create_channel("b", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    // Reverse the order, so "a" (created first) now holds position 1, not 0.
    app.clone()
        .oneshot(request(
            "PUT",
            "/channels/order",
            Some(&token),
            Some(json!({ "channel_ids": [b.id.to_string(), a.id.to_string()] })),
        ))
        .await
        .unwrap();

    let created = json_body(
        app.clone()
            .oneshot(request(
                "POST",
                "/channels",
                Some(&token),
                Some(json!({ "name": "c" })),
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(created["position"].as_i64().unwrap(), 2);

    let listed = json_body(
        app.clone()
            .oneshot(request("GET", "/channels", Some(&token), None))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(
        ids(&listed),
        vec![
            b.id.to_string(),
            a.id.to_string(),
            created["id"].as_str().unwrap().to_owned(),
        ]
    );
}

#[tokio::test]
async fn reordering_without_manage_channels_is_forbidden() {
    let (store, _guard) = new_store().await;
    store
        .create_role("everyone", Permissions::VIEW_CHANNEL, true)
        .await
        .unwrap();
    let a = store.create_channel("a", "text").await.unwrap();
    let b = store.create_channel("b", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "PUT",
            "/channels/order",
            Some(&token),
            Some(json!({ "channel_ids": [b.id.to_string(), a.id.to_string()] })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

/// A list missing a live channel is refused with a 400 naming it, rather than
/// silently leaving a gap in the order.
#[tokio::test]
async fn reorder_refuses_a_list_missing_a_live_channel() {
    let (store, _guard) = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::MANAGE_CHANNELS),
            true,
        )
        .await
        .unwrap();
    let a = store.create_channel("a", "text").await.unwrap();
    let b = store.create_channel("b", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "PUT",
            "/channels/order",
            Some(&token),
            Some(json!({ "channel_ids": [a.id.to_string()] })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let body = json_body(response).await;
    let error = body["error"].as_str().unwrap();
    assert!(error.contains("missing"));
    assert!(error.contains(&b.id.to_string()));
}

/// An id that names no live channel is refused, distinctly from a missing one.
#[tokio::test]
async fn reorder_refuses_an_unknown_channel_id() {
    let (store, _guard) = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::MANAGE_CHANNELS),
            true,
        )
        .await
        .unwrap();
    let a = store.create_channel("a", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    let bogus = Uuid::now_v7().to_string();
    let response = app
        .clone()
        .oneshot(request(
            "PUT",
            "/channels/order",
            Some(&token),
            Some(json!({ "channel_ids": [a.id.to_string(), bogus.clone()] })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let body = json_body(response).await;
    let error = body["error"].as_str().unwrap();
    assert!(error.contains("unknown"));
    assert!(error.contains(&bogus));
}

/// Repeating one channel and leaving another out entirely is refused, not
/// silently accepted with the repeat's last position winning.
#[tokio::test]
async fn reorder_refuses_a_duplicate_that_also_omits_a_channel() {
    let (store, _guard) = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::MANAGE_CHANNELS),
            true,
        )
        .await
        .unwrap();
    let a = store.create_channel("a", "text").await.unwrap();
    let b = store.create_channel("b", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "PUT",
            "/channels/order",
            Some(&token),
            Some(json!({ "channel_ids": [a.id.to_string(), a.id.to_string()] })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let body = json_body(response).await;
    assert!(body["error"].as_str().unwrap().contains(&b.id.to_string()));
}

/// A duplicate that still names every live channel at least once is refused
/// too: the length itself has to match, or a duplicate could silently pin
/// one channel's position while displacing nothing else's slot count.
#[tokio::test]
async fn reorder_refuses_a_duplicate_that_names_every_channel() {
    let (store, _guard) = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::MANAGE_CHANNELS),
            true,
        )
        .await
        .unwrap();
    let a = store.create_channel("a", "text").await.unwrap();
    let b = store.create_channel("b", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "PUT",
            "/channels/order",
            Some(&token),
            Some(json!({
                "channel_ids": [a.id.to_string(), b.id.to_string(), a.id.to_string()]
            })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

/// A DM is never in the ordered set: naming it is refused the same way an
/// unknown id is, and it never has to appear in a valid list.
#[tokio::test]
async fn reorder_never_names_a_dm_channel() {
    let (store, _guard) = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::MANAGE_CHANNELS),
            true,
        )
        .await
        .unwrap();
    let a = store.create_channel("a", "text").await.unwrap();
    let alice = store.create_user("alice", "alice").await.unwrap();
    let bob = store.create_user("bob", "bob").await.unwrap();
    let dm = store.open_dm(alice.id, bob.id).await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "carol").await;

    // The DM is not required alongside `a`.
    let response = app
        .clone()
        .oneshot(request(
            "PUT",
            "/channels/order",
            Some(&token),
            Some(json!({ "channel_ids": [a.id.to_string()] })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    // Naming it anyway is refused, like any other unknown id.
    let response = app
        .clone()
        .oneshot(request(
            "PUT",
            "/channels/order",
            Some(&token),
            Some(json!({ "channel_ids": [a.id.to_string(), dm.id.to_string()] })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

/// Submitting the order the deployment already has changes nothing and still
/// answers 200 with that same order - not an error, and not a claim that
/// something moved when it did not.
#[tokio::test]
async fn reordering_to_the_same_order_is_a_no_op() {
    let (store, _guard) = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::MANAGE_CHANNELS),
            true,
        )
        .await
        .unwrap();
    let a = store.create_channel("a", "text").await.unwrap();
    let b = store.create_channel("b", "text").await.unwrap();
    let app = app(store.clone());
    let token = register(&store, "alice").await;

    let same_order = vec![a.id.to_string(), b.id.to_string()];
    let response = app
        .clone()
        .oneshot(request(
            "PUT",
            "/channels/order",
            Some(&token),
            Some(json!({ "channel_ids": same_order.clone() })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(ids(&json_body(response).await), same_order);
}
