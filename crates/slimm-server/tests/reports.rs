// SPDX-License-Identifier: AGPL-3.0-only
//! Report triage: MANAGE_MESSAGES gates both the queue and resolving one, and
//! nobody below that bar ever sees a report's content snapshot.

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::ids::{ChannelId, UserId};
use slimm_server::permissions::Permissions;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use tower::ServiceExt;
use uuid::Uuid;

mod support;

async fn new_store() -> (Store, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new("slimm-reports-test");
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

/// A member with a session, built straight through the store.
///
/// Deliberately not the `/auth/register` route: joining a claimed deployment
/// is an invite-gated policy decision, and it is pinned by its own tests in
/// `registration_gate.rs`. These tests only need somebody signed in, so going
/// through the store keeps them independent of that policy.
async fn register(store: &Store, username: &str) -> (String, String) {
    let account = store
        .create_account(username, username, "not-a-real-hash")
        .await
        .unwrap();
    // The first account through here claims the deployment, exactly as the
    // first real registration does; later ones find it already set up.
    store.bootstrap_deployment(account.id).await.unwrap();
    let tokens = store.open_session(account.id, "cli").await.unwrap();
    (tokens.access_token, account.id.to_string())
}

async fn general_channel_id(store: &Store) -> String {
    store
        .list_channels()
        .await
        .unwrap()
        .into_iter()
        .next()
        .expect("bootstrap seeds a general channel")
        .id
        .to_string()
}

/// Sends a message as `token` and files a report on it as `reporter_token`,
/// returning the report id.
async fn file_a_report(
    app: &Router,
    channel_id: &str,
    author_token: &str,
    reporter_token: &str,
    content: &str,
) -> String {
    let sent = json_body(
        app.clone()
            .oneshot(request(
                "POST",
                &format!("/channels/{channel_id}/messages"),
                Some(author_token),
                Some(json!({ "id": Uuid::now_v7().to_string(), "content": content })),
            ))
            .await
            .unwrap(),
    )
    .await;
    let message_id = sent["id"].as_str().unwrap();

    let filed = app
        .clone()
        .oneshot(request(
            "POST",
            "/reports",
            Some(reporter_token),
            Some(json!({
                "subject_kind": "message",
                "subject_id": message_id,
                "reason": "spam"
            })),
        ))
        .await
        .unwrap();
    assert_eq!(filed.status(), StatusCode::OK);
    json_body(filed).await["id"].as_str().unwrap().to_owned()
}

// --- Gating ---

#[tokio::test]
async fn listing_and_resolving_require_manage_messages() {
    let (store, _guard) = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let (bob_token, _bob_id) = register(&store, "bob").await;
    let (carol_token, _carol_id) = register(&store, "carol").await;
    let channel_id = general_channel_id(&store).await;
    let report_id = file_a_report(
        &app,
        &channel_id,
        &bob_token,
        &carol_token,
        "secret content",
    )
    .await;

    let list = app
        .clone()
        .oneshot(request("GET", "/reports", Some(&bob_token), None))
        .await
        .unwrap();
    assert_eq!(list.status(), StatusCode::FORBIDDEN);

    let resolve = app
        .clone()
        .oneshot(request(
            "PATCH",
            &format!("/reports/{report_id}"),
            Some(&bob_token),
            Some(json!({ "resolution": "resolved" })),
        ))
        .await
        .unwrap();
    assert_eq!(resolve.status(), StatusCode::FORBIDDEN);

    // An administrator (MANAGE_MESSAGES via ADMINISTRATOR) can do both.
    let admin_list = app
        .clone()
        .oneshot(request("GET", "/reports", Some(&admin_token), None))
        .await
        .unwrap();
    assert_eq!(admin_list.status(), StatusCode::OK);
}

// --- Happy path and the queue's lifecycle ---

#[tokio::test]
async fn the_queue_carries_the_snapshot_and_resolving_removes_it() {
    let (store, _guard) = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let (bob_token, _bob_id) = register(&store, "bob").await;
    let (carol_token, _carol_id) = register(&store, "carol").await;
    let channel_id = general_channel_id(&store).await;
    let report_id = file_a_report(
        &app,
        &channel_id,
        &bob_token,
        &carol_token,
        "the reported text",
    )
    .await;

    let listed = json_body(
        app.clone()
            .oneshot(request("GET", "/reports", Some(&admin_token), None))
            .await
            .unwrap(),
    )
    .await;
    let reports = listed.as_array().unwrap();
    assert_eq!(reports.len(), 1);
    assert_eq!(reports[0]["id"], report_id);
    assert_eq!(reports[0]["snapshot"], "the reported text");
    assert_eq!(reports[0]["subject_kind"], "message");
    assert_eq!(reports[0]["reason"], "spam");

    let resolve = app
        .clone()
        .oneshot(request(
            "PATCH",
            &format!("/reports/{report_id}"),
            Some(&admin_token),
            Some(json!({ "resolution": "resolved" })),
        ))
        .await
        .unwrap();
    assert_eq!(resolve.status(), StatusCode::NO_CONTENT);

    let after = json_body(
        app.clone()
            .oneshot(request("GET", "/reports", Some(&admin_token), None))
            .await
            .unwrap(),
    )
    .await;
    assert!(
        after.as_array().unwrap().is_empty(),
        "a resolved report leaves the open queue"
    );

    // Resolving it again finds nothing left to close.
    let again = app
        .clone()
        .oneshot(request(
            "PATCH",
            &format!("/reports/{report_id}"),
            Some(&admin_token),
            Some(json!({ "resolution": "dismissed" })),
        ))
        .await
        .unwrap();
    assert_eq!(again.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn resolution_must_be_resolved_or_dismissed() {
    let (store, _guard) = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let (bob_token, _bob_id) = register(&store, "bob").await;
    let (carol_token, _carol_id) = register(&store, "carol").await;
    let channel_id = general_channel_id(&store).await;
    let report_id = file_a_report(&app, &channel_id, &bob_token, &carol_token, "x").await;

    let response = app
        .clone()
        .oneshot(request(
            "PATCH",
            &format!("/reports/{report_id}"),
            Some(&admin_token),
            Some(json!({ "resolution": "ignored" })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn resolving_a_nonexistent_report_is_not_found() {
    let (store, _guard) = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;

    let response = app
        .clone()
        .oneshot(request(
            "PATCH",
            &format!("/reports/{}", Uuid::now_v7()),
            Some(&admin_token),
            Some(json!({ "resolution": "resolved" })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

/// Listing already hides a report from a moderator denied MANAGE_MESSAGES in
/// the channel it came from, because the queue carries the reported content
/// verbatim. Resolving checked only the deployment-wide permission, so that
/// same moderator could still dismiss reports from the one channel they were
/// deliberately kept out of, quietly emptying its queue.
#[tokio::test]
async fn a_report_you_cannot_read_is_one_you_cannot_resolve_either() {
    let (store, _guard) = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let (bob_token, _bob_id) = register(&store, "bob").await;
    let (carol_token, carol_id) = register(&store, "carol").await;
    let channel_id = general_channel_id(&store).await;

    // Carol moderates the deployment, but is denied it in this channel.
    let moderator = store
        .create_role("moderator", Permissions::MANAGE_MESSAGES, false)
        .await
        .unwrap();
    let carol = UserId(Uuid::parse_str(&carol_id).unwrap());
    store.assign_role(carol, moderator).await.unwrap();
    let channel = ChannelId(Uuid::parse_str(&channel_id).unwrap());
    store
        .set_member_overwrite(
            channel,
            carol,
            Permissions::NONE,
            Permissions::MANAGE_MESSAGES,
        )
        .await
        .unwrap();

    let report_id = file_a_report(&app, &channel_id, &bob_token, &admin_token, "reported").await;

    // She cannot see it.
    let listed = json_body(
        app.clone()
            .oneshot(request("GET", "/reports", Some(&carol_token), None))
            .await
            .unwrap(),
    )
    .await;
    assert!(
        listed.as_array().unwrap().is_empty(),
        "the queue already hides a report from a channel she cannot moderate"
    );

    // And cannot close it either. Answered as missing rather than forbidden, so
    // the endpoint does not confirm the report exists.
    let refused = app
        .clone()
        .oneshot(request(
            "PATCH",
            &format!("/reports/{report_id}"),
            Some(&carol_token),
            Some(json!({ "resolution": "dismissed" })),
        ))
        .await
        .unwrap();
    assert_eq!(refused.status(), StatusCode::NOT_FOUND);

    // The report is untouched, so a moderator who may act on it still can.
    let closed = app
        .clone()
        .oneshot(request(
            "PATCH",
            &format!("/reports/{report_id}"),
            Some(&admin_token),
            Some(json!({ "resolution": "resolved" })),
        ))
        .await
        .unwrap();
    assert_eq!(closed.status(), StatusCode::NO_CONTENT);
}

/// A report about a message in a DM must reach the deployment's moderators.
///
/// It did not: `list` and `resolve` re-check MANAGE_MESSAGES in the report's
/// own channel, and a DM channel grants that to nobody, so intake returned 200
/// while the report was invisible and unresolvable forever. This is the exact
/// black hole the audit found, in the one place harassment is most private.
#[tokio::test]
async fn a_report_filed_in_a_dm_reaches_the_moderators() {
    let (store, _guard) = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let (bob_token, bob_id) = register(&store, "bob").await;
    let (_carol_token, carol_id) = register(&store, "carol").await;

    let bob = UserId(Uuid::parse_str(&bob_id).unwrap());
    let carol = UserId(Uuid::parse_str(&carol_id).unwrap());
    let dm = store.open_dm(bob, carol).await.expect("open dm");
    let message_id = slimm_server::ids::MessageId(Uuid::now_v7());
    store
        .send_message(dm.id, bob, message_id, "abuse", &[])
        .await
        .expect("send in dm");

    let filed = app
        .clone()
        .oneshot(request(
            "POST",
            "/reports",
            Some(&bob_token),
            Some(json!({
                "subject_kind": "message",
                "subject_id": message_id.0.to_string(),
                "reason": "reporting my own dm message for the test",
            })),
        ))
        .await
        .unwrap();
    assert_eq!(filed.status(), StatusCode::OK, "intake accepts it");
    let report_id = json_body(filed).await["id"].as_str().unwrap().to_string();

    let queue = app
        .clone()
        .oneshot(request("GET", "/reports", Some(&admin_token), None))
        .await
        .unwrap();
    let rows = json_body(queue).await;
    assert_eq!(
        rows.as_array().unwrap().len(),
        1,
        "the DM report is in the moderator queue, not a black hole"
    );

    let closed = app
        .clone()
        .oneshot(request(
            "PATCH",
            &format!("/reports/{report_id}"),
            Some(&admin_token),
            Some(json!({ "resolution": "resolved" })),
        ))
        .await
        .unwrap();
    assert_eq!(
        closed.status(),
        StatusCode::NO_CONTENT,
        "and a moderator can close it"
    );
}

/// A report about a message in a channel that is later deleted stays visible.
///
/// Same root cause as the DM case: a soft-deleted channel resolves to NONE, so
/// the per-channel re-check dropped the report out of the queue on delete.
#[tokio::test]
async fn a_report_survives_its_channel_being_deleted() {
    let (store, _guard) = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let channel_id = general_channel_id(&store).await;

    let extra = store.create_channel("scratch", "text").await.unwrap();
    let report_id = file_a_report(
        &app,
        &extra.id.to_string(),
        &admin_token,
        &admin_token,
        "worth keeping across a delete",
    )
    .await;

    let deleted = app
        .clone()
        .oneshot(request(
            "DELETE",
            &format!("/channels/{}", extra.id),
            Some(&admin_token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(deleted.status(), StatusCode::NO_CONTENT);

    let queue = app
        .clone()
        .oneshot(request("GET", "/reports", Some(&admin_token), None))
        .await
        .unwrap();
    let rows = json_body(queue).await;
    assert!(
        rows.as_array()
            .unwrap()
            .iter()
            .any(|r| r["id"] == report_id.as_str()),
        "the report is still in the queue after its channel was deleted"
    );
    let _ = channel_id;
}

/// A `user`-subject report about an id that never named an account is refused.
///
/// It was accepted with no existence check and no foreign key, so the queue
/// could be flooded with reports naming random uuids.
#[tokio::test]
async fn a_report_about_a_nonexistent_user_is_refused() {
    let (store, _guard) = new_store().await;
    let app = app(store.clone());
    let (bob_token, _bob_id) = register(&store, "bob").await;

    let filed = app
        .clone()
        .oneshot(request(
            "POST",
            "/reports",
            Some(&bob_token),
            Some(json!({
                "subject_kind": "user",
                "subject_id": Uuid::now_v7().to_string(),
                "reason": "nobody by this id exists",
            })),
        ))
        .await
        .unwrap();
    assert_eq!(filed.status(), StatusCode::NOT_FOUND);
}
