// SPDX-License-Identifier: AGPL-3.0-only
//! The screen-share height ceiling as a space setting: its default, the
//! config round trip over HTTP, its MANAGE_SERVER gate, and the settable
//! range. Enforcement is client-advertised; see
//! `client/packages/rtc/lib/src/screen_share_control.dart`, not this crate.

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
use slimm_server::store::{MAX_SCREEN_SHARE_MAX_HEIGHT, MIN_SCREEN_SHARE_MAX_HEIGHT, Store};
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

/// The default a deployment keeps on upgrade is the top of the settable
/// range, so behaviour is unchanged - no client-visible cap - until an admin
/// lowers it.
#[tokio::test]
async fn the_cap_defaults_to_the_top_of_the_range() {
    let (s, _guard) = harness("slimm-screen-share-cap-default").await;
    assert_eq!(
        s.screen_share_max_height().await.unwrap(),
        MAX_SCREEN_SHARE_MAX_HEIGHT
    );
}

#[tokio::test]
async fn the_cap_round_trips_over_http() {
    let (s, _guard) = harness("slimm-screen-share-cap-roundtrip").await;
    let admin = register(&s, "root").await;
    let session = s.open_session(admin, "laptop").await.unwrap();
    let router = app(s);

    let response = router
        .clone()
        .oneshot(request(
            "PATCH",
            "/space/screen-share",
            &session.access_token,
            Some(json!({"max_height": 720})),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(json_body(response).await["max_height"], json!(720));

    let response = router
        .oneshot(request(
            "GET",
            "/space/screen-share",
            &session.access_token,
            None,
        ))
        .await
        .unwrap();
    assert_eq!(json_body(response).await["max_height"], json!(720));
}

#[tokio::test]
async fn updating_the_cap_requires_manage_server() {
    let (s, _guard) = harness("slimm-screen-share-cap-forbidden").await;
    let _admin = register(&s, "root").await;
    let member = s.create_user("nia", "Nia").await.unwrap();
    let session = s.open_session(member.id, "phone").await.unwrap();
    let router = app(s);

    let response = router
        .oneshot(request(
            "PATCH",
            "/space/screen-share",
            &session.access_token,
            Some(json!({"max_height": 720})),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn an_out_of_range_cap_is_refused() {
    let (s, _guard) = harness("slimm-screen-share-cap-range").await;
    let admin = register(&s, "root").await;
    let session = s.open_session(admin, "laptop").await.unwrap();
    let router = app(s);

    for bad in [
        MIN_SCREEN_SHARE_MAX_HEIGHT - 1,
        MAX_SCREEN_SHARE_MAX_HEIGHT + 1,
    ] {
        let response = router
            .clone()
            .oneshot(request(
                "PATCH",
                "/space/screen-share",
                &session.access_token,
                Some(json!({ "max_height": bad })),
            ))
            .await
            .unwrap();
        assert_eq!(
            response.status(),
            StatusCode::BAD_REQUEST,
            "a max_height of {bad} is out of range and must be refused"
        );
    }
}

/// The other side of the same boundary: exactly `MIN_SCREEN_SHARE_MAX_HEIGHT`
/// and exactly `MAX_SCREEN_SHARE_MAX_HEIGHT` must both be accepted, or a `<`
/// that drifted to `<=` on one edge would pass `an_out_of_range_cap_is_refused`
/// while still refusing a value the range is supposed to allow.
#[tokio::test]
async fn the_range_boundaries_themselves_are_accepted() {
    let (s, _guard) = harness("slimm-screen-share-cap-boundaries").await;
    let admin = register(&s, "root").await;
    let session = s.open_session(admin, "laptop").await.unwrap();
    let router = app(s);

    for good in [MIN_SCREEN_SHARE_MAX_HEIGHT, MAX_SCREEN_SHARE_MAX_HEIGHT] {
        let response = router
            .clone()
            .oneshot(request(
                "PATCH",
                "/space/screen-share",
                &session.access_token,
                Some(json!({ "max_height": good })),
            ))
            .await
            .unwrap();
        assert_eq!(
            response.status(),
            StatusCode::OK,
            "a max_height of {good} is exactly at the boundary and must be accepted"
        );
    }
}
