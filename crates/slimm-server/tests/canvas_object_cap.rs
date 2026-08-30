// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The per-channel canvas object cap as a space setting: its default, the
//! config round trip over HTTP, its MANAGE_SERVER gate, and the settable
//! range. The cap's actual enforcement at placement is covered in
//! `canvas_write/write.rs` (`a_lowered_cap_refuses_the_next_object`).

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
use slimm_server::media::Media;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::{
    MAX_CANVAS_OBJECT_CAP, MAX_OBJECTS_PER_CHANNEL, MIN_CANVAS_OBJECT_CAP, Store,
};
use slimm_server::voice::VoiceService;
use tower::ServiceExt;

mod support;

async fn harness(name: &str) -> (Store, support::TestDbGuard) {
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
        voice: VoiceService::disabled(),
        media: Media::for_tests(),
        gifs: slimm_server::http::gifs::GifSearch::disabled(),
    })
}

fn request(method: &str, uri: &str, token: &str, body: Option<Value>) -> Request<Body> {
    let builder = Request::builder()
        .method(method)
        .uri(uri)
        .header("authorization", format!("Bearer {token}"));
    match body {
        Some(v) => builder
            .header("content-type", "application/json")
            .body(Body::from(v.to_string()))
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

/// The first account bootstraps the deployment and so holds MANAGE_SERVER.
async fn register(store: &Store, username: &str) -> UserId {
    let account = store
        .create_account(username, username, "not-a-real-hash")
        .await
        .unwrap();
    store.bootstrap_deployment(account.id).await.unwrap();
    account.id
}

/// The default a deployment keeps on upgrade is the compile-time object
/// ceiling, so behaviour is unchanged until an admin sets its own. Pins the
/// migration DEFAULT to the constant, which is otherwise free to drift.
#[tokio::test]
async fn the_cap_defaults_to_the_object_ceiling() {
    let (s, _guard) = harness("slimm-canvas-cap-default").await;
    assert_eq!(
        s.canvas_object_cap().await.unwrap(),
        MAX_OBJECTS_PER_CHANNEL
    );
}

#[tokio::test]
async fn the_cap_round_trips_over_http() {
    let (s, _guard) = harness("slimm-canvas-cap-roundtrip").await;
    let admin = register(&s, "root").await;
    let session = s.open_session(admin, "laptop").await.unwrap();
    let router = app(s);

    let response = router
        .clone()
        .oneshot(request(
            "PATCH",
            "/space/canvas-cap",
            &session.access_token,
            Some(json!({"object_cap": 5000})),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(json_body(response).await["object_cap"], json!(5000));

    let response = router
        .oneshot(request(
            "GET",
            "/space/canvas-cap",
            &session.access_token,
            None,
        ))
        .await
        .unwrap();
    assert_eq!(json_body(response).await["object_cap"], json!(5000));
}

#[tokio::test]
async fn updating_the_cap_requires_manage_server() {
    let (s, _guard) = harness("slimm-canvas-cap-forbidden").await;
    let _admin = register(&s, "root").await;
    let member = s.create_user("nia", "Nia").await.unwrap();
    let session = s.open_session(member.id, "phone").await.unwrap();
    let router = app(s);

    let response = router
        .oneshot(request(
            "PATCH",
            "/space/canvas-cap",
            &session.access_token,
            Some(json!({"object_cap": 5000})),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn an_out_of_range_cap_is_refused() {
    let (s, _guard) = harness("slimm-canvas-cap-range").await;
    let admin = register(&s, "root").await;
    let session = s.open_session(admin, "laptop").await.unwrap();
    let router = app(s);

    for bad in [MIN_CANVAS_OBJECT_CAP - 1, MAX_CANVAS_OBJECT_CAP + 1] {
        let response = router
            .clone()
            .oneshot(request(
                "PATCH",
                "/space/canvas-cap",
                &session.access_token,
                Some(json!({ "object_cap": bad })),
            ))
            .await
            .unwrap();
        assert_eq!(
            response.status(),
            StatusCode::BAD_REQUEST,
            "a cap of {bad} is out of range and must be refused"
        );
    }
}
