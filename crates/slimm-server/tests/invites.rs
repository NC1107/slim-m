// SPDX-License-Identifier: AGPL-3.0-only
//! Integration tests for invites: the permission gate, the use limit under
//! concurrency, expiry, and the deliberately uninformative check endpoint.

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

async fn new_store() -> Store {
    let path = std::env::temp_dir()
        .join(format!("slimm-invite-test-{}.db", uuid::Uuid::now_v7()))
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

fn app(store: Store) -> Router {
    http::router(AppState {
        store,
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: slimm_server::voice::VoiceService::disabled(),
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

/// An admin (via the bootstrap claim) and an ordinary member.
async fn fixture() -> (Store, Router, String, String) {
    let store = new_store().await;
    let auth = Auth::new(2).unwrap();
    let hash = auth
        .hash_password("hunter2hunter2".to_owned())
        .await
        .unwrap();
    let admin = store.create_account("admin", "Admin", &hash).await.unwrap();
    store.bootstrap_deployment(admin.id).await.unwrap();
    let member = store
        .create_account("member", "Member", &hash)
        .await
        .unwrap();

    let admin_session = store.open_session(admin.id, "d").await.unwrap();
    let member_session = store.open_session(member.id, "d").await.unwrap();
    let app = app(store.clone());
    (
        store,
        app,
        admin_session.access_token,
        member_session.access_token,
    )
}

#[tokio::test]
async fn only_a_permitted_member_can_create_invites() {
    let (_store, app, admin, member) = fixture().await;

    let created = app
        .clone()
        .oneshot(request("POST", "/invites", Some(&admin), Some(json!({}))))
        .await
        .unwrap();
    assert_eq!(created.status(), StatusCode::OK);
    let invite = json_body(created).await;
    assert!(invite["code"].as_str().unwrap().len() >= 8);
    assert_eq!(invite["usable"], true);

    // @everyone does not get CREATE_INVITE from the bootstrap defaults.
    let refused = app
        .clone()
        .oneshot(request("POST", "/invites", Some(&member), Some(json!({}))))
        .await
        .unwrap();
    assert_eq!(refused.status(), StatusCode::FORBIDDEN);

    // Listing is gated the same way.
    let listing = app
        .clone()
        .oneshot(request("GET", "/invites", Some(&member), None))
        .await
        .unwrap();
    assert_eq!(listing.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn the_use_limit_holds_and_a_spent_invite_stops_working() {
    let (store, app, admin, member) = fixture().await;

    let invite = json_body(
        app.clone()
            .oneshot(request(
                "POST",
                "/invites",
                Some(&admin),
                Some(json!({ "max_uses": 1 })),
            ))
            .await
            .unwrap(),
    )
    .await;
    let code = invite["code"].as_str().unwrap().to_owned();

    // Usable before anyone spends it.
    let check = json_body(
        app.clone()
            .oneshot(request(
                "GET",
                &format!("/invites/{code}/check"),
                None,
                None,
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(check["usable"], true);

    let redeemed = app
        .clone()
        .oneshot(request(
            "POST",
            &format!("/invites/{code}/redeem"),
            Some(&member),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(redeemed.status(), StatusCode::NO_CONTENT);

    // The single use is gone, so a second redemption fails and the check says so.
    let again = app
        .clone()
        .oneshot(request(
            "POST",
            &format!("/invites/{code}/redeem"),
            Some(&admin),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(again.status(), StatusCode::BAD_REQUEST);
    assert!(!store.invite_is_usable(&code).await.unwrap());
}

#[tokio::test]
async fn concurrent_redemptions_cannot_exceed_the_limit() {
    let (store, _app, _admin, _member) = fixture().await;
    let auth = Auth::new(2).unwrap();
    let hash = auth
        .hash_password("hunter2hunter2".to_owned())
        .await
        .unwrap();

    let creator = store.create_account("creator", "C", &hash).await.unwrap();
    let invite = store
        .create_invite(creator.id, None, Some(2), None)
        .await
        .unwrap();

    // Five people race for two slots.
    let mut joiners = Vec::new();
    for i in 0..5 {
        joiners.push(
            store
                .create_account(&format!("joiner{i}"), "J", &hash)
                .await
                .unwrap(),
        );
    }

    let mut handles = Vec::new();
    for joiner in joiners {
        let store = store.clone();
        let code = invite.code.clone();
        handles.push(tokio::spawn(async move {
            store.redeem_invite(&code, joiner.id).await.is_ok()
        }));
    }
    let mut succeeded = 0;
    for handle in handles {
        if handle.await.unwrap() {
            succeeded += 1;
        }
    }

    // The conditional UPDATE is what enforces this; without it two racing
    // redemptions could both read uses=1 and both write uses=2.
    assert_eq!(succeeded, 2, "exactly the two available slots were taken");
    assert!(!store.invite_is_usable(&invite.code).await.unwrap());
}

#[tokio::test]
async fn expiry_and_revocation_both_stop_an_invite() {
    let (store, app, admin, member) = fixture().await;
    let auth = Auth::new(2).unwrap();
    let hash = auth
        .hash_password("hunter2hunter2".to_owned())
        .await
        .unwrap();
    let creator = store.create_account("creator", "C", &hash).await.unwrap();

    // Already expired.
    let expired = store
        .create_invite(creator.id, None, None, Some(1))
        .await
        .unwrap();
    assert!(!store.invite_is_usable(&expired.code).await.unwrap());

    // Revoked while still otherwise valid.
    let live = json_body(
        app.clone()
            .oneshot(request("POST", "/invites", Some(&admin), Some(json!({}))))
            .await
            .unwrap(),
    )
    .await;
    let code = live["code"].as_str().unwrap().to_owned();
    assert!(store.invite_is_usable(&code).await.unwrap());

    let revoked = app
        .clone()
        .oneshot(request(
            "DELETE",
            &format!("/invites/{code}"),
            Some(&admin),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(revoked.status(), StatusCode::NO_CONTENT);
    assert!(!store.invite_is_usable(&code).await.unwrap());

    let refused = app
        .clone()
        .oneshot(request(
            "POST",
            &format!("/invites/{code}/redeem"),
            Some(&member),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(refused.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn checking_an_unknown_code_looks_the_same_as_a_spent_one() {
    let (_store, app, _admin, _member) = fixture().await;

    // A code that was never issued reports exactly what a used-up or expired one
    // reports, so the endpoint cannot be used to mine for valid codes.
    let unknown = json_body(
        app.clone()
            .oneshot(request("GET", "/invites/neverissued/check", None, None))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(unknown, json!({ "usable": false }));
    assert_eq!(
        unknown.as_object().unwrap().len(),
        1,
        "the response says nothing beyond usable"
    );
}
