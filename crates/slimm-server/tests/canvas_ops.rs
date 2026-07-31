// SPDX-License-Identifier: AGPL-3.0-only
//! The canvas op stream's catch-up feed: `place` writes one op per placement,
//! the feed pages them densely, and `reset` fires on all three triggers.
//!
//! Bulk fixtures go through `Store` directly rather than HTTP, the same
//! choice `canvas_write.rs`'s ceiling test makes, so a fixture that places or
//! seeds dozens of rows is not also a rate-limit test in disguise.

use std::fs;
use std::path::Path;

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::ids::{CanvasObjectId, ChannelId, UserId};
use slimm_server::media::Media;
use slimm_server::permissions::Permissions;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::{CANVAS_OP_GAP, CANVAS_OP_PAGE_BYTES, CanvasOpBody, Store};
use slimm_server::voice::VoiceService;
use tower::ServiceExt;
use uuid::Uuid;

mod support;

async fn new_store_and_pool() -> (Store, sqlx::SqlitePool, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new("slimm-canvas-ops");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    (Store::new(pool.clone()), pool, guard)
}

async fn new_store() -> (Store, support::TestDbGuard) {
    let (store, _pool, guard) = new_store_and_pool().await;
    (store, guard)
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
    })
}

async fn register(store: &Store, username: &str) -> (String, UserId) {
    let account = store
        .create_account(username, username, "not-a-real-hash")
        .await
        .unwrap();
    store.bootstrap_deployment(account.id).await.unwrap();
    let tokens = store.open_session(account.id, "cli").await.unwrap();
    (tokens.access_token, account.id)
}

async fn general(store: &Store) -> ChannelId {
    store.list_channels().await.unwrap()[0].id
}

fn stroke(id: &str) -> Value {
    json!({
        "id": id, "kind": "stroke",
        "x": 10.0, "y": 20.0, "w": 30.0, "h": 40.0,
        "props": { "points": [0.0, 0.0, 30.0, 40.0], "width": 3.0, "color": "annotation" },
    })
}

fn id() -> String {
    Uuid::now_v7().to_string()
}

async fn post_object(
    app: &Router,
    channel: ChannelId,
    token: &str,
    body: Value,
) -> (StatusCode, Value) {
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/channels/{channel}/canvas/objects"))
                .header("authorization", format!("Bearer {token}"))
                .header("content-type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

async fn get_ops(
    app: &Router,
    channel: ChannelId,
    token: &str,
    query: &str,
) -> (StatusCode, Value) {
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/channels/{channel}/canvas/ops?{query}"))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

/// Places directly through the store, bypassing the HTTP rate limiter.
async fn place(
    store: &Store,
    channel: ChannelId,
    author: UserId,
    props_bytes: usize,
) -> CanvasObjectId {
    let id = CanvasObjectId::generate();
    let props = if props_bytes == 0 {
        "{}".to_owned()
    } else {
        serde_json::to_string(&json!({ "filler": "x".repeat(props_bytes) })).unwrap()
    };
    store
        .place_canvas_object(channel, author, id, "stroke", (0.0, 0.0, 1.0, 1.0), &props)
        .await
        .expect("placed");
    id
}

// --- HTTP-level: gating, validation, and the route wired end to end ---

/// Seeing a channel is not seeing its canvas ops, exactly as the viewport
/// read already requires: `VIEW_CHANNEL` alone must not be enough.
#[tokio::test]
async fn reading_the_ops_feed_needs_the_canvas_bit_as_well_as_the_view_bit() {
    let (store, _guard) = new_store().await;
    store
        .create_role("everyone", Permissions::VIEW_CHANNEL, true)
        .await
        .unwrap();
    let drawers = store
        .create_role("drawers", Permissions::USE_CANVAS, false)
        .await
        .unwrap();
    let app = app(store.clone());
    let channel = store.create_channel("canvas", "voice").await.unwrap().id;

    let (token, user) = register(&store, "ann").await;
    let (status, body) = get_ops(&app, channel, &token, "after_seq=0").await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");

    store.assign_role(user, drawers).await.unwrap();
    let (status, body) = get_ops(&app, channel, &token, "after_seq=0").await;
    assert_eq!(status, StatusCode::OK, "{body}");
}

#[tokio::test]
async fn a_negative_after_seq_is_refused() {
    let (store, _guard) = new_store().await;
    let (token, _) = register(&store, "root").await;
    let channel = general(&store).await;

    let (status, body) = get_ops(&app(store), channel, &token, "after_seq=-1").await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
}

/// The end-to-end path: a real HTTP placement writes an op the feed then
/// pages back, over the real route rather than the store method directly.
#[tokio::test]
async fn the_feed_is_dense_over_place_ops_placed_over_http() {
    let (store, _guard) = new_store().await;
    let (token, _) = register(&store, "root").await;
    let channel = general(&store).await;
    let app = app(store.clone());

    for _ in 0..5 {
        let (status, _) = post_object(&app, channel, &token, stroke(&id())).await;
        assert_eq!(status, StatusCode::CREATED);
    }

    let (status, body) = get_ops(&app, channel, &token, "after_seq=0").await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let ops = body["ops"].as_array().unwrap();
    assert_eq!(ops.len(), 5);
    let seqs: Vec<i64> = ops.iter().map(|o| o["seq"].as_i64().unwrap()).collect();
    assert_eq!(
        seqs,
        vec![1, 2, 3, 4, 5],
        "the sequence must be dense with no gap"
    );
    assert!(ops.iter().all(|o| o["kind"] == "place"));
    assert_eq!(body["latest_seq"], 5);
    assert_eq!(body["has_more"], false);
    assert_eq!(body["reset"], false);
}

// --- Store-level: object liveness, reset triggers, pagination, anonymization ---

#[tokio::test]
async fn a_place_ops_object_is_present_and_matches_what_was_placed() {
    let (store, _guard) = new_store().await;
    let author = store.create_user("ann", "Ann").await.unwrap().id;
    let channel = store.create_channel("canvas", "voice").await.unwrap().id;
    let placed = place(&store, channel, author, 0).await;

    let page = store.list_canvas_ops(channel, 0, 100).await.unwrap();
    assert_eq!(page.ops.len(), 1);
    match &page.ops[0].body {
        CanvasOpBody::Place(Some(object)) => assert_eq!(object.id, placed),
        other => panic!("expected a live place object, got {other:?}"),
    }
}

/// The subtlest line in the design: a `place` whose object has since been
/// removed carries no `object` at all, so a client never repaints something
/// the server no longer holds live.
#[tokio::test]
async fn a_place_ops_object_is_absent_once_the_object_has_been_removed() {
    let (store, _guard) = new_store().await;
    let author = store.create_user("ann", "Ann").await.unwrap().id;
    let channel = store.create_channel("canvas", "voice").await.unwrap().id;
    let placed = place(&store, channel, author, 0).await;
    assert!(store.remove_canvas_object(placed).await.unwrap());

    let page = store.list_canvas_ops(channel, 0, 100).await.unwrap();
    assert_eq!(page.ops.len(), 1, "the op itself survives the removal");
    match &page.ops[0].body {
        CanvasOpBody::Place(None) => {}
        other => panic!("expected the object to read as gone, got {other:?}"),
    }
}

#[tokio::test]
async fn the_feed_resets_when_the_cursor_is_ahead_of_latest_seq() {
    let (store, _guard) = new_store().await;
    let author = store.create_user("ann", "Ann").await.unwrap().id;
    let channel = store.create_channel("canvas", "voice").await.unwrap().id;
    place(&store, channel, author, 0).await;

    let page = store.list_canvas_ops(channel, 100, 100).await.unwrap();
    assert!(page.reset, "after_seq past latest_seq must reset");
    assert_eq!(page.latest_seq, 1);
    assert!(page.ops.is_empty());
}

#[tokio::test]
async fn the_feed_resets_when_the_caller_is_too_far_behind() {
    let (store, pool, _guard) = new_store_and_pool().await;
    let author = store.create_user("ann", "Ann").await.unwrap().id;
    let channel = store.create_channel("canvas", "voice").await.unwrap().id;

    let total = CANVAS_OP_GAP + 5;
    sqlx::query(
        "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < ?)
         INSERT INTO canvas_ops (channel_id, seq, id, kind, actor_id, created_at)
         SELECT ?, i, randomblob(16), 'place', ?, 0 FROM n",
    )
    .bind(total)
    .bind(channel)
    .bind(author)
    .execute(&pool)
    .await
    .expect("seed the op stream");
    sqlx::query(
        "UPDATE channel_seq_counters SET next_seq = ? WHERE channel_id = ? AND stream = 'canvas'",
    )
    .bind(total + 1)
    .bind(channel)
    .execute(&pool)
    .await
    .expect("advance the counter to match");

    let page = store.list_canvas_ops(channel, 0, 100).await.unwrap();
    assert!(page.reset, "more than CANVAS_OP_GAP behind must reset");
    assert_eq!(page.latest_seq, total);
    assert!(page.ops.is_empty());
}

/// Simulates a future sweep by raw-deleting the earliest ops (nothing in
/// this slice does this yet), and checks the boundary precisely: one op
/// short of the floor resets, exactly caught up to it does not.
#[tokio::test]
async fn the_feed_resets_only_strictly_behind_the_retained_floor() {
    let (store, pool, _guard) = new_store_and_pool().await;
    let author = store.create_user("ann", "Ann").await.unwrap().id;
    let channel = store.create_channel("canvas", "voice").await.unwrap().id;
    for _ in 0..5 {
        place(&store, channel, author, 0).await;
    }
    sqlx::query("DELETE FROM canvas_ops WHERE channel_id = ? AND seq <= 2")
        .bind(channel)
        .execute(&pool)
        .await
        .expect("simulate a sweep raising the floor to 3");

    let behind = store.list_canvas_ops(channel, 1, 100).await.unwrap();
    assert!(behind.reset, "one op short of the floor is unrecoverable");
    assert!(behind.ops.is_empty());

    let at_floor = store.list_canvas_ops(channel, 2, 100).await.unwrap();
    assert!(
        !at_floor.reset,
        "exactly caught up to the floor must not reset"
    );
    assert_eq!(at_floor.ops[0].seq, 3);
}

/// The opposite end from the viewport read's own over-read trim: this feed
/// reads oldest-first, so a truncated page drops the newest row, and paging
/// forward from the last seq returned reaches every op with no gap or
/// repeat.
#[tokio::test]
async fn has_more_is_dropped_from_the_back_and_paging_continues_correctly() {
    let (store, _guard) = new_store().await;
    let author = store.create_user("ann", "Ann").await.unwrap().id;
    let channel = store.create_channel("canvas", "voice").await.unwrap().id;
    for _ in 0..5 {
        place(&store, channel, author, 0).await;
    }

    let first = store.list_canvas_ops(channel, 0, 2).await.unwrap();
    assert_eq!(
        first.ops.iter().map(|o| o.seq).collect::<Vec<_>>(),
        vec![1, 2]
    );
    assert!(first.has_more);

    let second = store.list_canvas_ops(channel, 2, 2).await.unwrap();
    assert_eq!(
        second.ops.iter().map(|o| o.seq).collect::<Vec<_>>(),
        vec![3, 4]
    );
    assert!(second.has_more);

    let third = store.list_canvas_ops(channel, 4, 2).await.unwrap();
    assert_eq!(third.ops.iter().map(|o| o.seq).collect::<Vec<_>>(), vec![5]);
    assert!(!third.has_more);
}

/// A page bounded only by row count still varies three orders of magnitude
/// in bytes, since a `place` op carries whole props at up to `MAX_PROPS_BYTES`
/// while every other kind carries none.
#[tokio::test]
async fn a_page_stops_early_once_place_props_cross_the_byte_budget() {
    let (store, _guard) = new_store().await;
    let author = store.create_user("ann", "Ann").await.unwrap().id;
    let channel = store.create_channel("canvas", "voice").await.unwrap().id;

    // Comfortably past MAX_PROPS_BYTES (4 KiB) each, so well under 140 crosses CANVAS_OP_PAGE_BYTES.
    let placed_count = 140;
    for _ in 0..placed_count {
        place(&store, channel, author, 4_000).await;
    }

    let page = store.list_canvas_ops(channel, 0, 200).await.unwrap();
    assert!(
        page.ops.len() < placed_count,
        "the byte budget must stop the page before the row limit, got {} ops",
        page.ops.len()
    );
    assert!(page.has_more, "a budget-truncated page must say so");

    let total_bytes: usize = page
        .ops
        .iter()
        .map(|op| match &op.body {
            CanvasOpBody::Place(Some(object)) => object.props.len(),
            _ => 0,
        })
        .sum();
    assert!(
        total_bytes <= CANVAS_OP_PAGE_BYTES + 4_100,
        "the page must not run far past the byte budget: {total_bytes} bytes"
    );
}

#[tokio::test]
async fn account_deletion_nulls_the_actor_id_of_a_placed_op() {
    let (store, _guard) = new_store().await;
    let author = store.create_user("ann", "Ann").await.unwrap().id;
    let channel = store.create_channel("canvas", "voice").await.unwrap().id;
    place(&store, channel, author, 0).await;

    store.delete_account(author).await.unwrap();

    let page = store.list_canvas_ops(channel, 0, 100).await.unwrap();
    assert_eq!(
        page.ops[0].actor_id, None,
        "a deleted account must not stay named as the actor of a canvas op"
    );
}

/// The page and its `latest_seq` share one snapshot only if every read in
/// `list_canvas_ops` goes through the transaction it opens, never `&self.pool`
/// directly. A race between two real async tasks is not a reliable way to
/// catch a regression here (SQLite's own writes are fast enough that the
/// window rarely lands), so this reads the source the way
/// `canvas_index.rs` reads the viewport query rather than timing anything.
#[test]
fn the_ops_feed_reads_only_through_one_transaction() {
    let source =
        fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("src/store/canvas_ops.rs"))
            .expect("read the canvas ops store module");
    assert!(
        !source.contains("&self.pool"),
        "a direct pool read here would race the transaction the feed's snapshot depends on"
    );
    assert_eq!(
        source.matches("self.pool.begin()").count(),
        1,
        "the feed must open exactly one transaction for its floor, latest_seq and page reads"
    );
}
