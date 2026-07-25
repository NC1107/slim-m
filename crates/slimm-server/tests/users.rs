// SPDX-License-Identifier: AGPL-3.0-only
//! Public user profiles, the batch lookup, and the member list: the narrow
//! public shape, consistent answers for a deleted account, and bounded
//! batches.

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use tower::ServiceExt;
use uuid::Uuid;

async fn new_store() -> Store {
    let path = format!("/tmp/slimm-users-test-{}.db", Uuid::now_v7());
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
    let body = json_body(response).await;
    (
        body["access_token"].as_str().unwrap().to_owned(),
        body["user_id"].as_str().unwrap().to_owned(),
    )
}

#[tokio::test]
async fn a_profile_carries_only_the_public_shape() {
    let store = new_store().await;
    let app = app(store);
    let (token, alice_id) = register(&app, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "GET",
            &format!("/users/{alice_id}"),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = json_body(response).await;

    assert_eq!(body["id"], alice_id);
    assert_eq!(body["username"], "alice");
    assert_eq!(body["display_name"], "alice");
    assert!(body["created_at"].is_i64());
    // Nothing from the auth tables leaks onto the wire.
    assert!(body.get("password_hash").is_none());
    assert!(body.get("email").is_none());
}

/// A deleted account answers exactly like an id that was never used: 404
/// either way, so this cannot be used to confirm someone deleted their
/// account.
#[tokio::test]
async fn a_deleted_account_looks_like_one_that_never_existed() {
    let store = new_store().await;
    let app = app(store.clone());
    let (token, _my_id) = register(&app, "alice").await;
    let (_bob_token, bob_id) = register(&app, "bob").await;

    let never_existed = Uuid::now_v7().to_string();

    let missing_status = app
        .clone()
        .oneshot(request(
            "GET",
            &format!("/users/{never_existed}"),
            Some(&token),
            None,
        ))
        .await
        .unwrap()
        .status();

    let bob_user_id = slimm_server::ids::UserId(Uuid::parse_str(&bob_id).unwrap());
    store.delete_account(bob_user_id).await.unwrap();

    let deleted_status = app
        .clone()
        .oneshot(request(
            "GET",
            &format!("/users/{bob_id}"),
            Some(&token),
            None,
        ))
        .await
        .unwrap()
        .status();

    assert_eq!(missing_status, StatusCode::NOT_FOUND);
    assert_eq!(deleted_status, missing_status);
}

#[tokio::test]
async fn batch_lookup_skips_ids_with_nothing_to_report() {
    let store = new_store().await;
    let app = app(store);
    let (token, alice_id) = register(&app, "alice").await;
    let (_, bob_id) = register(&app, "bob").await;
    let never_existed = Uuid::now_v7().to_string();

    let response = app
        .clone()
        .oneshot(request(
            "GET",
            &format!("/users?ids={alice_id},{bob_id},{never_existed}"),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = json_body(response).await;
    let ids: Vec<&str> = body
        .as_array()
        .unwrap()
        .iter()
        .map(|u| u["id"].as_str().unwrap())
        .collect();
    assert_eq!(ids.len(), 2, "the never-existed id is simply absent");
    assert!(ids.contains(&alice_id.as_str()));
    assert!(ids.contains(&bob_id.as_str()));
}

#[tokio::test]
async fn an_empty_batch_returns_an_empty_list() {
    let store = new_store().await;
    let app = app(store);
    let (token, _id) = register(&app, "alice").await;

    let response = app
        .clone()
        .oneshot(request("GET", "/users", Some(&token), None))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = json_body(response).await;
    assert_eq!(body.as_array().unwrap().len(), 0);
}

#[tokio::test]
async fn a_batch_over_the_cap_is_rejected() {
    let store = new_store().await;
    let app = app(store);
    let (token, _id) = register(&app, "alice").await;

    let ids: Vec<String> = (0..101).map(|_| Uuid::now_v7().to_string()).collect();
    let response = app
        .clone()
        .oneshot(request(
            "GET",
            &format!("/users?ids={}", ids.join(",")),
            Some(&token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn an_unparseable_id_in_the_batch_is_a_bad_request() {
    let store = new_store().await;
    let app = app(store);
    let (token, _id) = register(&app, "alice").await;

    let response = app
        .clone()
        .oneshot(request("GET", "/users?ids=not-a-uuid", Some(&token), None))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn the_member_list_is_paginated_and_bounded() {
    let store = new_store().await;
    let app = app(store);
    let (token, first_id) = register(&app, "alice").await;
    let (_, second_id) = register(&app, "bob").await;
    let (_, third_id) = register(&app, "carol").await;

    let first_page = json_body(
        app.clone()
            .oneshot(request("GET", "/members?limit=2", Some(&token), None))
            .await
            .unwrap(),
    )
    .await;
    let first_page = first_page.as_array().unwrap();
    assert_eq!(first_page.len(), 2);
    assert_eq!(first_page[0]["id"], first_id);
    assert_eq!(first_page[1]["id"], second_id);

    let cursor = first_page[1]["id"].as_str().unwrap();
    let second_page = json_body(
        app.clone()
            .oneshot(request(
                "GET",
                &format!("/members?after={cursor}&limit=2"),
                Some(&token),
                None,
            ))
            .await
            .unwrap(),
    )
    .await;
    let second_page = second_page.as_array().unwrap();
    assert_eq!(second_page.len(), 1);
    assert_eq!(second_page[0]["id"], third_id);
}

#[tokio::test]
async fn the_member_list_requires_authentication() {
    let store = new_store().await;
    let app = app(store);

    let response = app
        .clone()
        .oneshot(request("GET", "/members", None, None))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
