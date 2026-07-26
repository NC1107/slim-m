// SPDX-License-Identifier: AGPL-3.0-only
//! Integration tests for account deletion: anonymization, revocation, and the
//! HTTP endpoint.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::json;
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::ids::MessageId;
use slimm_server::permissions::Permissions;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::{OpenError, RefreshOutcome, Store};
use tower::ServiceExt;

async fn new_store() -> Store {
    let path = std::env::temp_dir()
        .join(format!("slimm-account-test-{}.db", uuid::Uuid::now_v7()))
        .to_string_lossy()
        .into_owned();
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        push_relay_url: None,
        push_relay_key: None,
        livekit_url: None,
        livekit_api_key: None,
        livekit_api_secret: None,
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    Store::new(pool)
}

#[tokio::test]
async fn delete_account_anonymizes_content_and_revokes_access() {
    let store = new_store().await;
    let auth = Auth::new(2).unwrap();
    let hash = auth
        .hash_password("correct horse battery".to_owned())
        .await
        .unwrap();
    let account = store.create_account("alice", "Alice", &hash).await.unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let tokens = store.open_session(account.id, "laptop").await.unwrap();
    let message = store
        .send_message(channel.id, account.id, MessageId::generate(), "hello")
        .await
        .unwrap()
        .message;

    // Before: the token works, the message is authored by alice, login exists.
    assert!(
        store
            .authenticate(&tokens.access_token)
            .await
            .unwrap()
            .is_some()
    );
    assert_eq!(
        store.message(message.id).await.unwrap().unwrap().author_id,
        Some(account.id)
    );
    assert!(store.find_credentials("alice").await.unwrap().is_some());

    let revoked = store.delete_account(account.id).await.unwrap();
    assert_eq!(revoked.len(), 1, "the one open session is revoked");

    // The access token no longer resolves and refresh is denied.
    assert!(
        store
            .authenticate(&tokens.access_token)
            .await
            .unwrap()
            .is_none()
    );
    assert!(matches!(
        store.rotate_refresh(&tokens.refresh_token).await.unwrap(),
        RefreshOutcome::Denied
    ));

    // The account cannot log in (tombstoned) and the username frees up.
    assert!(store.find_credentials("alice").await.unwrap().is_none());
    assert!(
        store
            .create_account("alice", "New Alice", "x")
            .await
            .is_ok(),
        "the freed username can be registered again"
    );

    // The message survives in the channel, but authorship is cleared.
    let message = store.message(message.id).await.unwrap().unwrap();
    assert_eq!(message.content, "hello");
    assert_eq!(message.author_id, None);
}

#[tokio::test]
async fn open_session_refuses_a_deleted_account() {
    let store = new_store().await;
    let account = store
        .create_account("alice", "Alice", "hash")
        .await
        .unwrap();
    store.delete_account(account.id).await.unwrap();

    // Even resolving the tombstoned user, a login cannot open a fresh session,
    // so a login racing the deletion cannot escape it.
    let result = store.open_session(account.id, "device").await;
    assert!(matches!(result, Err(OpenError::AccountGone)));
}

#[tokio::test]
async fn delete_account_purges_member_channel_overwrites() {
    let store = new_store().await;
    store
        .create_role("everyone", Permissions::VIEW_CHANNEL, true)
        .await
        .unwrap();
    let account = store
        .create_account("alice", "Alice", "hash")
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    store
        .set_member_overwrite(
            channel.id,
            account.id,
            Permissions::NONE,
            Permissions::VIEW_CHANNEL,
        )
        .await
        .unwrap();

    // While the account exists, its member overwrite denies view.
    assert!(
        !store
            .has_permission(account.id, channel.id, Permissions::VIEW_CHANNEL)
            .await
            .unwrap()
    );

    store.delete_account(account.id).await.unwrap();

    // The member overwrite row is purged, so it no longer affects evaluation.
    assert!(
        store
            .has_permission(account.id, channel.id, Permissions::VIEW_CHANNEL)
            .await
            .unwrap()
    );
}

#[tokio::test]
async fn http_delete_account_rejects_the_token_afterward() {
    let store = new_store().await;
    let app = http::router(AppState {
        store,
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: slimm_server::voice::VoiceService::disabled(),
    });

    // Register and grab the access token.
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "username": "bob",
                        "display_name": "Bob",
                        "password": "hunter2hunter2",
                        "device_name": "cli"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let access = json["access_token"].as_str().unwrap().to_owned();

    // Delete the account.
    let deleted = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri("/account")
                .header("authorization", format!("Bearer {access}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(deleted.status(), StatusCode::NO_CONTENT);

    // The same token is now rejected everywhere.
    let after = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/auth/ws-ticket")
                .header("authorization", format!("Bearer {access}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(after.status(), StatusCode::UNAUTHORIZED);
}

/// The last administrator cannot delete themselves out of a deployment other
/// people are still using: roles, invites and moderation all need a bit nobody
/// would hold afterwards, and there is no recovery path from that state.
#[tokio::test]
async fn the_last_administrator_cannot_strand_a_populated_deployment() {
    let store = new_store().await;
    let app = http::router(AppState {
        store,
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: slimm_server::voice::VoiceService::disabled(),
    });

    let signup = |username: &'static str, invite: Option<String>| {
        let app = app.clone();
        async move {
            let mut body = json!({
                "username": username,
                "display_name": username,
                "password": "hunter2hunter2",
                "device_name": "cli"
            });
            if let Some(code) = invite {
                body["invite_code"] = json!(code);
            }
            let response = app
                .oneshot(
                    Request::builder()
                        .method("POST")
                        .uri("/auth/register")
                        .header("content-type", "application/json")
                        .body(Body::from(body.to_string()))
                        .unwrap(),
                )
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::OK);
            let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
                .await
                .unwrap();
            let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
            json["access_token"].as_str().unwrap().to_owned()
        }
    };

    // The first account claims the deployment and becomes its administrator.
    let admin = signup("admin", None).await;

    // A second, ordinary member: somebody who would be stranded. Joining a
    // claimed deployment takes an invite, so the admin issues one.
    let created = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/invites")
                .header("authorization", format!("Bearer {admin}"))
                .header("content-type", "application/json")
                .body(Body::from(json!({}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(created.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(created.into_body(), usize::MAX)
        .await
        .unwrap();
    let invite: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let code = invite["code"].as_str().unwrap().to_owned();

    let _member = signup("member", Some(code)).await;

    let refused = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri("/account")
                .header("authorization", format!("Bearer {admin}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        refused.status(),
        StatusCode::CONFLICT,
        "deleting the only administrator while others remain must be refused, and as a \
         conflict rather than a server error"
    );

    // The account is still usable, not left half-deleted.
    let still_working = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/channels")
                .header("authorization", format!("Bearer {admin}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(still_working.status(), StatusCode::OK);
}
