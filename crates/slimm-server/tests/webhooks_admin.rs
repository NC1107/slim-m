// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Minting, listing, renaming and revoking webhooks: the MANAGE_SERVER gate,
//! the one-time delivery path, and revocation taking effect immediately.
//!
//! Delivery itself, and the uniform 404 it gives an unknown or revoked
//! credential, is `tests/webhooks.rs`'s job; this file only covers the admin
//! routes `http/webhooks_admin.rs` adds on top of it.

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
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use tower::ServiceExt;

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
    serde_json::from_slice(&bytes).unwrap_or(Value::Null)
}

/// An administrator with a session, the deployment claimed by them, and a
/// channel to point webhooks at.
async fn admin(store: &Store, username: &str) -> (UserId, String, String) {
    let account = store
        .create_account(username, username, "not-a-real-hash")
        .await
        .unwrap();
    store.bootstrap_deployment(account.id).await.unwrap();
    let token = store
        .open_session(account.id, "cli")
        .await
        .unwrap()
        .access_token;
    let channel = store.create_channel("general", "text").await.unwrap();
    (account.id, token, channel.id.to_string())
}

#[tokio::test]
async fn manage_server_can_mint_list_rename_and_revoke_a_webhook() {
    let (store, _guard) = new_store("slimm-webhooks-admin-lifecycle").await;
    let (_admin_id, root, channel_id) = admin(&store, "root").await;
    let app = app(store);

    let created = json_body(
        app.clone()
            .oneshot(request(
                "POST",
                "/webhooks",
                &root,
                Some(json!({ "channel_id": channel_id, "label": "alerts" })),
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(created["webhook"]["label"], "alerts");
    assert_eq!(created["webhook"]["channel_id"], channel_id);
    let delivery_path = created["delivery_path"].as_str().unwrap();
    assert!(
        delivery_path.starts_with("/webhooks/"),
        "the mint response must carry a pasteable delivery path exactly once"
    );
    let webhook_id = created["webhook"]["id"].as_str().unwrap().to_owned();

    let listing = json_body(
        app.clone()
            .oneshot(request("GET", "/webhooks", &root, None))
            .await
            .unwrap(),
    )
    .await;
    let entries = listing.as_array().unwrap();
    assert_eq!(entries.len(), 1);
    assert!(
        entries[0].get("delivery_path").is_none() && entries[0].get("token").is_none(),
        "a listing must never carry a webhook's credential again"
    );
    assert_eq!(entries[0]["created_by_display_name"], "root");

    let renamed = json_body(
        app.clone()
            .oneshot(request(
                "PATCH",
                &format!("/webhooks/{webhook_id}"),
                &root,
                Some(json!({ "label": "renamed-alerts" })),
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(renamed["label"], "renamed-alerts");

    let revoked = app
        .clone()
        .oneshot(request(
            "POST",
            &format!("/webhooks/{webhook_id}/revoke"),
            &root,
            None,
        ))
        .await
        .unwrap();
    assert_eq!(revoked.status(), StatusCode::NO_CONTENT);

    let delivery = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(delivery_path)
                .header("content-type", "application/json")
                .body(Body::from(json!({ "content": "too late" }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        delivery.status(),
        StatusCode::NOT_FOUND,
        "revocation must take effect immediately"
    );
}

#[tokio::test]
async fn an_ordinary_member_cannot_provision_list_or_revoke_webhooks() {
    let (store, _guard) = new_store("slimm-webhooks-admin-member").await;
    let (_admin_id, root, channel_id) = admin(&store, "root").await;
    let member = store.create_user("mallory", "Mallory").await.unwrap();
    let token = store
        .open_session(member.id, "laptop")
        .await
        .unwrap()
        .access_token;
    let app = app(store.clone());

    let minted = store
        .create_webhook(
            slimm_server::ids::ChannelId(uuid::Uuid::parse_str(&channel_id).unwrap()),
            "alerts",
            _admin_id,
        )
        .await
        .unwrap();

    for (method, uri, body) in [
        (
            "POST",
            "/webhooks".to_owned(),
            Some(json!({ "channel_id": channel_id, "label": "sneaky" })),
        ),
        ("GET", "/webhooks".to_owned(), None),
        (
            "POST",
            format!("/webhooks/{}/revoke", minted.webhook.id),
            None,
        ),
    ] {
        let response = app
            .clone()
            .oneshot(request(method, &uri, &token, body))
            .await
            .unwrap();
        assert_eq!(
            response.status(),
            StatusCode::FORBIDDEN,
            "{method} {uri} needs MANAGE_SERVER"
        );
    }

    let _ = root; // root only exists to stand up the deployment for this fixture.
}

#[tokio::test]
async fn creating_a_webhook_on_an_unknown_channel_answers_404() {
    let (store, _guard) = new_store("slimm-webhooks-admin-unknown-channel").await;
    let (_admin_id, root, _channel_id) = admin(&store, "root").await;
    let app = app(store);

    let response = app
        .oneshot(request(
            "POST",
            "/webhooks",
            &root,
            Some(json!({
                "channel_id": uuid::Uuid::now_v7().to_string(),
                "label": "alerts",
            })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}
