// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! `POST /members/bulk-removal` and `POST /members/bulk-timeout`.
//!
//! The rules worth pinning are the ones that would rot silently: that the
//! batch is refused as a whole rather than part-applied, that containment is
//! checked per target so bulk is exactly as strong as the single verb, and
//! that the audit trail records one row per member rather than one per act.

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
    let (path, guard) = support::TestDbGuard::new("slimm-member-bulk-test");
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

fn post(uri: &str, token: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri(uri)
        .header("authorization", format!("Bearer {token}"))
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

struct People {
    admin_id: String,
    mod_token: String,
    mod_id: String,
    members: Vec<String>,
}

/// An admin, a moderator holding exactly the two moderation bits, and three
/// ordinary members to act on.
async fn people(store: &Store) -> People {
    let admin = store
        .create_account("root", "Root", "not-a-real-hash")
        .await
        .unwrap();
    store.bootstrap_deployment(admin.id).await.unwrap();

    let mod_role = store
        .create_role(
            "mod",
            Permissions::KICK_MEMBERS.union(Permissions::BAN_MEMBERS),
            false,
        )
        .await
        .unwrap();
    let moderator = store
        .create_account("mod", "Mod", "not-a-real-hash")
        .await
        .unwrap();
    store.assign_role(moderator.id, mod_role).await.unwrap();
    let mod_token = store
        .open_session(moderator.id, "cli")
        .await
        .unwrap()
        .access_token;

    let mut members = Vec::new();
    for name in ["nia", "ola", "pim"] {
        let account = store
            .create_account(name, name, "not-a-real-hash")
            .await
            .unwrap();
        members.push(account.id.to_string());
    }

    People {
        admin_id: admin.id.to_string(),
        mod_token,
        mod_id: moderator.id.to_string(),
        members,
    }
}

/// How many removals are in force, read through the store rather than the
/// route so the assertion does not depend on the listing's own permissions.
async fn removal_count(store: &Store) -> usize {
    store.list_removals().await.unwrap().len()
}

/// Audit rows carrying `action`, out of the merged history feed.
async fn audit_actions(store: &Store, action: &str) -> usize {
    store
        .moderation_history(None, &[], 50)
        .await
        .unwrap()
        .iter()
        .filter(|item| match item {
            slimm_server::store::ModerationHistoryItem::Audit(entry) => entry.action == action,
            _ => false,
        })
        .count()
}

#[tokio::test]
async fn removes_every_member_named() {
    let (store, _guard) = new_store().await;
    let p = people(&store).await;
    let app = app(store.clone());

    let response = app
        .oneshot(post(
            "/members/bulk-removal",
            &p.mod_token,
            json!({ "user_ids": p.members, "reason": "raid" }),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT);
    assert_eq!(removal_count(&store).await, 3);
}

/// The containment rule, checked per target. Without this a moderator removes
/// an administrator by burying them in a list of ordinary members.
#[tokio::test]
async fn one_target_above_the_caller_refuses_the_whole_batch() {
    let (store, _guard) = new_store().await;
    let p = people(&store).await;
    let app = app(store.clone());

    let mut ids = p.members.clone();
    ids.push(p.admin_id.clone());

    let response = app
        .oneshot(post(
            "/members/bulk-removal",
            &p.mod_token,
            json!({ "user_ids": ids }),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
    // The ordinary members listed before the admin must be untouched.
    assert_eq!(removal_count(&store).await, 0);
}

#[tokio::test]
async fn times_out_every_member_named_to_the_same_deadline() {
    let (store, _guard) = new_store().await;
    let p = people(&store).await;
    let app = app(store.clone());

    let response = app
        .oneshot(post(
            "/members/bulk-timeout",
            &p.mod_token,
            json!({ "user_ids": p.members, "duration_seconds": 300 }),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    let mut deadlines = Vec::new();
    for id in &p.members {
        let user_id: uuid::Uuid = id.parse().unwrap();
        let timeout = store
            .member_timeout(slimm_server::ids::UserId(user_id))
            .await
            .unwrap()
            .expect("timed out");
        deadlines.push(timeout.until);
    }
    assert_eq!(deadlines.len(), 3);
    assert!(
        deadlines.windows(2).all(|w| w[0] == w[1]),
        "one batch must share one deadline, got {deadlines:?}"
    );
}

/// One row per member, so the trail answers "what was done to this person".
#[tokio::test]
async fn writes_one_audit_row_per_member() {
    let (store, _guard) = new_store().await;
    let p = people(&store).await;
    let app = app(store.clone());

    app.oneshot(post(
        "/members/bulk-removal",
        &p.mod_token,
        json!({ "user_ids": p.members }),
    ))
    .await
    .unwrap();

    assert_eq!(audit_actions(&store, "remove").await, 3);
}

/// A repeated id is one act, not two audit rows for the same person.
#[tokio::test]
async fn duplicate_ids_collapse() {
    let (store, _guard) = new_store().await;
    let p = people(&store).await;
    let app = app(store.clone());

    let target = p.members[0].clone();
    let response = app
        .oneshot(post(
            "/members/bulk-removal",
            &p.mod_token,
            json!({ "user_ids": [target.clone(), target] }),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    assert_eq!(audit_actions(&store, "remove").await, 1);
}

#[tokio::test]
async fn refuses_an_empty_list_and_an_over_long_one() {
    let (store, _guard) = new_store().await;
    let p = people(&store).await;
    let app = app(store.clone());

    let empty = app
        .clone()
        .oneshot(post(
            "/members/bulk-removal",
            &p.mod_token,
            json!({ "user_ids": [] }),
        ))
        .await
        .unwrap();
    assert_eq!(empty.status(), StatusCode::BAD_REQUEST);

    let too_many: Vec<String> = (0..65).map(|_| uuid::Uuid::now_v7().to_string()).collect();
    let over = app
        .oneshot(post(
            "/members/bulk-removal",
            &p.mod_token,
            json!({ "user_ids": too_many }),
        ))
        .await
        .unwrap();
    assert_eq!(over.status(), StatusCode::BAD_REQUEST);
}

/// Self-moderation is refused on the bulk path exactly as on the single one.
#[tokio::test]
async fn refuses_the_caller_in_their_own_batch() {
    let (store, _guard) = new_store().await;
    let p = people(&store).await;
    let app = app(store.clone());

    let response = app
        .oneshot(post(
            "/members/bulk-removal",
            &p.mod_token,
            json!({ "user_ids": [p.members[0].clone(), p.mod_id.clone()] }),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    assert_eq!(removal_count(&store).await, 0);
}
