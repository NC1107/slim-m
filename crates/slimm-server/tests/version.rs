// SPDX-License-Identifier: AGPL-3.0-only
//! GET /version: the unauthenticated probe onboarding uses to learn what a
//! server is before an account exists, including whether it can deliver push.

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::Value;
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use tower::ServiceExt;

async fn new_store() -> Store {
    let path = std::env::temp_dir()
        .join(format!("slimm-version-test-{}.db", uuid::Uuid::now_v7()))
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

fn app(store: Store, push: PushSender) -> Router {
    http::router(AppState {
        store,
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push,
        voice: slimm_server::voice::VoiceService::disabled(),
        media: slimm_server::media::Media::for_tests(),
    })
}

async fn get_version(app: Router) -> Value {
    let response = app
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/version")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

#[tokio::test]
async fn version_reports_push_disabled_without_a_relay() {
    let body = get_version(app(new_store().await, PushSender::disabled())).await;

    assert_eq!(body["name"], "slim-m");
    assert_eq!(body["protocol"], 1);
    assert!(body["version"].is_string());
    assert_eq!(body["push_enabled"], false);
}

#[tokio::test]
async fn version_reports_push_enabled_with_a_relay() {
    let config = Config {
        port: 0,
        database_path: String::new(),
        hash_concurrency: 2,
        push_relay_url: Some("https://relay.example".into()),
        push_relay_key: Some("smr_test".into()),
        ..Config::default()
    };
    let push = PushSender::new(&config).expect("relay config is valid");

    let body = get_version(app(new_store().await, push)).await;
    assert_eq!(body["push_enabled"], true);
}
