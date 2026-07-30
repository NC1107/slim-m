// SPDX-License-Identifier: AGPL-3.0-only
//! The two read surfaces that answered with as much as a deployment happened
//! to hold, and the write-time ceiling that replaced paging for one of them.
//!
//! Neither was reachable without a permission, so neither is a way in from
//! outside. What they are is a cost that scales with how much members have
//! done rather than with anything an operator chose, which is the same shape as
//! the unauthenticated bounds in `resource_bounds.rs` one privilege level up.
//!
//! Its own file rather than added to `pins.rs` (433 lines) or `reports.rs`
//! (373): both are past the review budget already.

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::Value;
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::ids::{ChannelId, MessageId, UserId};
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::{MAX_PINS_PER_CHANNEL, PinError, Store};
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
    })
}

fn get(uri: &str, token: &str) -> Request<Body> {
    Request::builder()
        .method("GET")
        .uri(uri)
        .header("authorization", format!("Bearer {token}"))
        .body(Body::empty())
        .unwrap()
}

async fn json_array(app: &Router, uri: &str, token: &str) -> Vec<Value> {
    let response = app.clone().oneshot(get(uri, token)).await.unwrap();
    assert_eq!(response.status(), StatusCode::OK, "GET {uri}");
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

/// An administrator with a session, and the deployment claimed by them.
async fn admin(store: &Store, username: &str) -> (UserId, String, ChannelId) {
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
    let channel = store.list_channels().await.unwrap()[0].id;
    (account.id, token, channel)
}

async fn message(store: &Store, channel: ChannelId, author: UserId, body: &str) -> MessageId {
    store
        .send_message(channel, author, MessageId::generate(), body, &[])
        .await
        .unwrap()
        .message
        .id
}

// --- The moderation queue ---

/// The queue answered with every open report in the deployment, and the handler
/// then re-checks visibility channel by channel at several indexed queries
/// each. It answers one page now, and pages forward on `created_at`.
#[tokio::test]
async fn the_report_queue_answers_a_page_and_pages_forward() {
    let (store, _guard) = new_store("slimm-bounds-reports").await;
    let (moderator, token, channel) = admin(&store, "root").await;
    let reporter = store.create_user("bob", "Bob").await.unwrap();

    // One report per subject: the store allows only one open report per pair.
    for index in 0..7 {
        let subject = message(&store, channel, moderator, &format!("m{index}")).await;
        store
            .file_report(
                reporter.id,
                slimm_server::store::ReportSubject::Message(subject),
                "not ok",
            )
            .await
            .unwrap();
    }

    let first = json_array(&app(store.clone()), "/reports?limit=3", &token).await;
    assert_eq!(first.len(), 3, "a limit must bound the page");

    let last_seen = first.last().unwrap()["created_at"].as_i64().unwrap();
    let next = json_array(
        &app(store.clone()),
        &format!("/reports?limit=3&after={last_seen}"),
        &token,
    )
    .await;
    assert!(
        !next.is_empty(),
        "the cursor must reach the rest of the queue"
    );
    let first_ids: Vec<&str> = first.iter().map(|r| r["id"].as_str().unwrap()).collect();
    for report in &next {
        assert!(
            !first_ids.contains(&report["id"].as_str().unwrap()),
            "a page must not repeat the previous one"
        );
    }
}

/// A caller asking for everything gets a page, not everything. Without the
/// clamp the limit is the caller's to choose, which is the same unbounded read
/// with an extra step.
#[tokio::test]
async fn an_absurd_report_limit_is_clamped() {
    let (store, _guard) = new_store("slimm-bounds-report-limit").await;
    let (moderator, token, channel) = admin(&store, "root").await;
    let reporter = store.create_user("bob", "Bob").await.unwrap();
    for index in 0..4 {
        let subject = message(&store, channel, moderator, &format!("m{index}")).await;
        store
            .file_report(
                reporter.id,
                slimm_server::store::ReportSubject::Message(subject),
                "not ok",
            )
            .await
            .unwrap();
    }

    let all = json_array(&app(store.clone()), "/reports?limit=999999", &token).await;
    assert_eq!(all.len(), 4, "the clamp is a ceiling, not a floor");

    let zero = json_array(&app(store.clone()), "/reports?limit=0", &token).await;
    assert_eq!(
        zero.len(),
        1,
        "a limit under one clamps up, never to nothing"
    );
}

// --- Pins ---

/// A channel's pin set is bounded at the write rather than paged at the read,
/// so every reader can still have all of it. Driven through the store: the
/// point is the ceiling, and 200 pins through HTTP would be 200 round trips to
/// prove the same thing.
#[tokio::test]
async fn a_channel_refuses_a_pin_past_its_ceiling() {
    let (store, _guard) = new_store("slimm-bounds-pin-ceiling").await;
    let (author, _token, channel) = admin(&store, "root").await;

    let mut first = None;
    for index in 0..MAX_PINS_PER_CHANNEL {
        let id = message(&store, channel, author, &format!("m{index}")).await;
        store.pin_message(channel, id, author).await.unwrap();
        if first.is_none() {
            first = Some(id);
        }
    }

    let one_more = message(&store, channel, author, "one too many").await;
    assert!(
        matches!(
            store.pin_message(channel, one_more, author).await,
            Err(PinError::TooMany)
        ),
        "the ceiling must refuse, not silently drop"
    );

    // Idempotence must survive the ceiling, or a retry breaks when it is full.
    store
        .pin_message(channel, first.unwrap(), author)
        .await
        .expect("re-pinning an existing pin is not a new pin");

    assert_eq!(
        store.pin_count(channel).await.unwrap(),
        MAX_PINS_PER_CHANNEL
    );
}

#[tokio::test]
async fn the_pin_list_takes_a_limit() {
    let (store, _guard) = new_store("slimm-bounds-pin-limit").await;
    let (author, token, channel) = admin(&store, "root").await;
    for index in 0..5 {
        let id = message(&store, channel, author, &format!("m{index}")).await;
        store.pin_message(channel, id, author).await.unwrap();
    }

    let uri = format!("/channels/{channel}/pins?limit=2");
    let page = json_array(&app(store.clone()), &uri, &token).await;
    assert_eq!(page.len(), 2);

    let uri = format!("/channels/{channel}/pins");
    let all = json_array(&app(store.clone()), &uri, &token).await;
    assert_eq!(all.len(), 5, "no limit still answers the whole bounded set");
}

/// A DM's viewer check narrows the candidates to the pair before asking
/// anything per candidate. Correctness is already pinned by
/// `permissions.rs`'s equivalence test; what this adds is that a candidate
/// list far longer than the pair is answered the same way, which is the
/// property the two comments in that branch used to claim falsely.
#[tokio::test]
async fn a_dm_viewer_check_ignores_candidates_outside_the_pair() {
    let (store, _guard) = new_store("slimm-bounds-dm-viewers").await;
    let (alice, _token, _channel) = admin(&store, "alice").await;
    let bob = store.create_user("bob", "Bob").await.unwrap();
    let dm = store.open_dm(alice, bob.id).await.unwrap();

    let mut candidates = vec![alice, bob.id];
    for index in 0..20 {
        let stranger = store
            .create_user(&format!("s{index}"), "Stranger")
            .await
            .unwrap();
        candidates.push(stranger.id);
    }

    let viewers = store.viewers_among(dm.id, &candidates).await.unwrap();
    assert_eq!(viewers.len(), 2, "only the pair can view their own DM");
    assert!(viewers.contains(&alice) && viewers.contains(&bob.id));

    let strangers_only: Vec<UserId> = candidates.into_iter().skip(2).collect();
    assert!(
        store
            .viewers_among(dm.id, &strangers_only)
            .await
            .unwrap()
            .is_empty()
    );
}

/// A nonexistent id is not a report about anybody, so a bad cursor is not a way
/// to read past the page - it just yields nothing.
#[tokio::test]
async fn a_cursor_past_the_end_yields_nothing() {
    let (store, _guard) = new_store("slimm-bounds-cursor-end").await;
    let (_moderator, token, _channel) = admin(&store, "root").await;
    let uri = format!("/reports?after={}", i64::MAX);
    assert!(
        json_array(&app(store.clone()), &uri, &token)
            .await
            .is_empty()
    );
}
