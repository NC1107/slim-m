// SPDX-License-Identifier: AGPL-3.0-only
//! Placing a canvas object over HTTP: what it refuses, and what it promises a
//! caller who retries.
//!
//! The refusals are the point. This route sits behind a bit `@everyone` holds
//! by default and, in this slice, there is no way to remove what it writes, so
//! every ceiling here is one that cannot be walked back later.

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
use slimm_server::media::Media;
use slimm_server::permissions::Permissions;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::{MAX_OBJECT_EXTENT, MAX_OBJECTS_PER_CHANNEL, Store};
use slimm_server::voice::VoiceService;
use tower::ServiceExt;
use uuid::Uuid;

mod support;

async fn new_store() -> (Store, support::TestDbGuard) {
    let (store, _pool, guard) = new_store_and_pool().await;
    (store, guard)
}

async fn new_store_and_pool() -> (Store, sqlx::SqlitePool, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new("slimm-canvas-write");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    (Store::new(pool.clone()), pool, guard)
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

const QUERY: &str = "min_x=0&min_y=0&max_x=100&max_y=100&limit=2";

fn region(channel: ChannelId) -> String {
    format!("/channels/{channel}/canvas/objects")
}

async fn general(store: &Store) -> ChannelId {
    store.list_channels().await.unwrap()[0].id
}

async fn post(app: &Router, channel: ChannelId, token: &str, body: Value) -> (StatusCode, Value) {
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

fn stroke(id: &str) -> Value {
    json!({
        "id": id,
        "kind": "stroke",
        "x": 10.0, "y": 20.0, "w": 30.0, "h": 40.0,
        "props": { "points": [0.0, 0.0, 30.0, 40.0], "width": 3.0, "color": "annotation" },
    })
}

fn id() -> String {
    Uuid::now_v7().to_string()
}

#[tokio::test]
async fn a_placed_object_comes_straight_back_and_is_visible_to_a_viewport_read() {
    let (store, _guard) = new_store().await;
    let (token, _) = register(&store, "root").await;
    let channel = general(&store).await;
    let app = app(store.clone());

    let (status, body) = post(&app, channel, &token, stroke(&id())).await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(body["kind"], "stroke");
    assert_eq!(body["x"], 10.0);
    assert_eq!(body["seq"], 1);

    let objects = store
        .viewport_objects(
            channel,
            &slimm_server::store::ViewportQuery {
                view: slimm_server::store::Rect {
                    min_x: 0.0,
                    min_y: 0.0,
                    max_x: 100.0,
                    max_y: 100.0,
                },
                previous: None,
                after_seq: 0,
                limit: 10,
            },
        )
        .await
        .unwrap();
    assert_eq!(objects.len(), 1);
    assert_eq!(store.latest_canvas_seq(channel).await.unwrap(), 1);
}

/// Drawing is not the same permission as reading, and the write route has to
/// agree with the read route about that or the two disagree in the dangerous
/// direction: a member the viewport refuses could still add to the canvas.
#[tokio::test]
async fn placing_needs_the_canvas_bit_as_well_as_the_view_bit() {
    let (store, _guard) = new_store().await;
    let (_root, _root_id) = register(&store, "root").await;
    let channel = general(&store).await;

    let member = store
        .create_account("bob", "bob", "not-a-real-hash")
        .await
        .unwrap();
    let token = store
        .open_session(member.id, "cli")
        .await
        .unwrap()
        .access_token;
    store
        .set_member_overwrite(
            channel,
            member.id,
            Permissions::NONE,
            Permissions::USE_CANVAS,
        )
        .await
        .unwrap();

    let (status, _) = post(&app(store.clone()), channel, &token, stroke(&id())).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

/// The bit a timeout cannot express. `TIMEOUT_DENY` spares `USE_CANVAS` on
/// purpose, so without this check a timed-out member keeps drawing.
#[tokio::test]
async fn a_timed_out_member_can_still_read_the_canvas_and_cannot_draw_on_it() {
    let (store, _guard) = new_store().await;
    let (_root, root_id) = register(&store, "root").await;
    let channel = general(&store).await;
    let member = store
        .create_account("bob", "bob", "not-a-real-hash")
        .await
        .unwrap();
    let token = store
        .open_session(member.id, "cli")
        .await
        .unwrap()
        .access_token;
    let app = app(store.clone());

    let (status, _) = post(&app, channel, &token, stroke(&id())).await;
    assert_eq!(
        status,
        StatusCode::CREATED,
        "drawing works before a timeout"
    );

    let until = chrono_ms() + 60_000;
    store
        .set_member_timeout(member.id, until, Some("cool off"), root_id)
        .await
        .unwrap();

    let (status, _) = post(&app, channel, &token, stroke(&id())).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let permissions = store
        .permissions_in_channel(member.id, channel)
        .await
        .unwrap();
    assert!(
        permissions.contains(Permissions::USE_CANVAS),
        "the timeout must not blank the canvas, only freeze the pen",
    );
}

#[tokio::test]
async fn an_unknown_kind_is_refused_rather_than_stored_as_a_row_nobody_can_draw() {
    let (store, _guard) = new_store().await;
    let (token, _) = register(&store, "root").await;
    let channel = general(&store).await;
    let mut body = stroke(&id());
    body["kind"] = json!("window");

    let (status, _) = post(&app(store), channel, &token, body).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

/// Sized to sit between the props ceiling and the body limit, so only the
/// props check can be what refuses it: an earlier version of this test used a
/// body the byte-level limit rejected first, and dropping the props ceiling
/// left it green.
#[tokio::test]
async fn props_over_the_ceiling_are_refused_as_a_bad_request() {
    let (store, _guard) = new_store().await;
    let (token, _) = register(&store, "root").await;
    let channel = general(&store).await;
    let mut body = stroke(&id());
    body["props"] = json!({ "points": vec![1.25_f64; 900] });
    assert!(
        (4 * 1024..8 * 1024).contains(&serde_json::to_vec(&body).unwrap().len()),
        "the body must be over the props ceiling and under the body limit",
    );

    let (status, _) = post(&app(store), channel, &token, body).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

/// Past the body limit it is refused at the byte level, before serde ever
/// builds a `Value` several times the wire size out of it.
#[tokio::test]
async fn an_over_large_body_is_refused_before_it_is_parsed() {
    let (store, _guard) = new_store().await;
    let (token, _) = register(&store, "root").await;
    let channel = general(&store).await;
    let mut body = stroke(&id());
    body["props"] = json!({ "points": vec![1.25_f64; 4000] });

    let (status, _) = post(&app(store), channel, &token, body).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
}

/// The world is bounded (owner decision) and so is one object inside it. An
/// object legally spanning the world is written into every cell of a client's
/// spatial grid, which is a hang rather than a slow frame.
#[tokio::test]
async fn an_object_outside_the_world_or_larger_than_the_ceiling_is_refused() {
    let (store, _guard) = new_store().await;
    let (token, _) = register(&store, "root").await;
    let channel = general(&store).await;
    let app = app(store);

    let mut outside = stroke(&id());
    outside["x"] = json!(4_999_999.0);
    outside["w"] = json!(100.0);
    let (status, _) = post(&app, channel, &token, outside).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "outside the world");

    let mut huge = stroke(&id());
    huge["w"] = json!(MAX_OBJECT_EXTENT + 1.0);
    let (status, _) = post(&app, channel, &token, huge).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "wider than the ceiling");
}

/// Idempotent by id, the way a message send is, and specifically not a second
/// row: the seq must be the first one, or a retry silently reorders the canvas.
#[tokio::test]
async fn the_same_id_twice_yields_one_object_with_its_original_seq() {
    let (store, _guard) = new_store().await;
    let (token, _) = register(&store, "root").await;
    let channel = general(&store).await;
    let app = app(store.clone());
    let object = id();

    let (first, first_body) = post(&app, channel, &token, stroke(&object)).await;
    let (_, _) = post(&app, channel, &token, stroke(&id())).await;
    let (second, second_body) = post(&app, channel, &token, stroke(&object)).await;

    assert_eq!(first, StatusCode::CREATED);
    assert_eq!(second, StatusCode::CREATED);
    assert_eq!(first_body["seq"], second_body["seq"]);
    assert_eq!(first_body["seq"], 1);
    assert_eq!(
        store.latest_canvas_seq(channel).await.unwrap(),
        2,
        "the replay must not consume a sequence value",
    );
}

#[tokio::test]
async fn the_same_id_in_another_channel_is_a_conflict() {
    let (store, _guard) = new_store().await;
    let (token, _) = register(&store, "root").await;
    let channel = general(&store).await;
    let other = store.create_channel("other", "text").await.unwrap();
    let app = app(store);
    let object = id();

    let (first, _) = post(&app, channel, &token, stroke(&object)).await;
    let (second, body) = post(&app, other.id, &token, stroke(&object)).await;
    assert_eq!(first, StatusCode::CREATED);
    assert_eq!(second, StatusCode::CONFLICT);
    assert_eq!(body["error"], "canvas object id already used");
}

/// A retry racing an erase deserves an honest answer, not the same "id
/// taken" a foreign-channel conflict gets: the two 409s must read
/// differently, or a client cannot explain either to the person drawing.
#[tokio::test]
async fn replaying_the_id_of_a_removed_object_answers_a_distinct_conflict() {
    let (store, _guard) = new_store().await;
    let (token, _) = register(&store, "root").await;
    let channel = general(&store).await;
    let app = app(store.clone());
    let object = id();

    let (status, body) = post(&app, channel, &token, stroke(&object)).await;
    assert_eq!(status, StatusCode::CREATED);
    let placed = body["id"].as_str().unwrap().parse::<Uuid>().unwrap();
    store
        .remove_canvas_object(slimm_server::ids::CanvasObjectId(placed))
        .await
        .unwrap();

    let (status, body) = post(&app, channel, &token, stroke(&object)).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["error"], "that object was removed");
    assert_ne!(
        body["error"], "canvas object id already used",
        "an erased-object retry must not read as a foreign-channel id conflict"
    );
}

/// A removed row keeps its id (the column is UNIQUE across live and dead
/// rows), so a replay that fell through to the insert would surface the
/// constraint violation as a 500 the moment anything ever removes an object.
#[tokio::test]
async fn replaying_the_id_of_a_removed_object_is_a_conflict_not_a_crash() {
    let (store, _guard) = new_store().await;
    let (token, _) = register(&store, "root").await;
    let channel = general(&store).await;
    let app = app(store.clone());
    let object = id();

    let (status, body) = post(&app, channel, &token, stroke(&object)).await;
    assert_eq!(status, StatusCode::CREATED);
    let placed = body["id"].as_str().unwrap().parse::<Uuid>().unwrap();
    store
        .remove_canvas_object(slimm_server::ids::CanvasObjectId(placed))
        .await
        .unwrap();

    let (status, _) = post(&app, channel, &token, stroke(&object)).await;
    assert_eq!(status, StatusCode::CONFLICT);
}

/// A truncated region must answer with the *newest* ink.
///
/// `z_index` is seeded from `seq`, so ordered ascending the limit dropped the
/// newest objects and kept a fixed prefix of old ones. That is invisible until
/// something writes: a busy region would then answer a reconnecting client
/// with everything except what had just been drawn, and the pane's recovery is
/// exactly a cold refetch.
#[tokio::test]
async fn a_truncated_region_answers_with_the_newest_objects() {
    let (store, _guard) = new_store().await;
    let (token, _) = register(&store, "root").await;
    let channel = general(&store).await;
    let app = app(store.clone());

    for _ in 0..5 {
        let (status, _) = post(&app, channel, &token, stroke(&id())).await;
        assert_eq!(status, StatusCode::CREATED);
    }

    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("{}?{}", region(channel), QUERY))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    assert_eq!(body["has_more"], true);
    let seqs: Vec<i64> = body["objects"]
        .as_array()
        .unwrap()
        .iter()
        .map(|o| o["seq"].as_i64().unwrap())
        .collect();
    assert_eq!(
        seqs,
        vec![4, 5],
        "the page must be the newest two, in paint order"
    );
}

/// The ceiling that cannot be walked back.
///
/// This slice ships no way to remove a canvas object - no erase, no
/// `MANAGE_CANVAS` path, no sweep - behind a bit `@everyone` holds, so an
/// unbounded write here would be permanent. Filled by raw insert rather than
/// twenty thousand round trips, since what is under test is the refusal.
#[tokio::test]
async fn a_full_canvas_refuses_the_next_object() {
    let (store, pool, _guard) = new_store_and_pool().await;
    let (token, author) = register(&store, "root").await;
    let channel = general(&store).await;

    sqlx::query(
        "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < ?)
         INSERT INTO canvas_objects
             (id, channel_id, channel_key, kind, z_index, x, y, w, h, props,
              author_id, seq, created_at)
         SELECT randomblob(16), ?, 0, 'stroke', i, 0, 0, 1, 1, '{}', ?, i, 0 FROM n",
    )
    .bind(MAX_OBJECTS_PER_CHANNEL)
    .bind(channel)
    .bind(author)
    .execute(&pool)
    .await
    .expect("filled the canvas");

    let (status, body) = post(&app(store), channel, &token, stroke(&id())).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["error"], "this canvas is full");
}

fn chrono_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as i64
}
