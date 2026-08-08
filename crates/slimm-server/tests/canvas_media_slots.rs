// SPDX-License-Identifier: AGPL-3.0-only
//! Shared, persistent media-tile placement: decision 0010's reversal.
//!
//! The owner's own test was explicit - move a tile, leave, come back
//! tomorrow, and it is still where it was left. `persists_across_a_restart`
//! is that test, driven against a fresh `Store` reconnected to the same
//! database file rather than the same process's in-memory state, so it
//! cannot pass by accident on a cache neither restart nor a real deployment
//! would have.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use futures_util::{SinkExt, StreamExt};
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
use tokio::net::TcpListener;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tower::ServiceExt;

mod support;

type Client =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

fn state_for(store: &Store) -> AppState {
    AppState {
        store: store.clone(),
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: slimm_server::voice::VoiceService::disabled(),
        media: slimm_server::media::Media::for_tests(),
    }
}

async fn user_ticket(store: &Store, name: &str) -> (String, String, UserId) {
    let user = store.create_user(name, name).await.unwrap();
    let tokens = store.open_session(user.id, "device").await.unwrap();
    let ctx = store
        .authenticate(&tokens.access_token)
        .await
        .unwrap()
        .unwrap();
    let (ticket, _expires_at) = store.mint_ws_ticket(&ctx).await.unwrap();
    (tokens.access_token, ticket, user.id)
}

async fn serve(state: AppState) -> std::net::SocketAddr {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, http::router(state)).await.unwrap();
    });
    addr
}

async fn connect(addr: std::net::SocketAddr, ticket: &str) -> Client {
    let (mut ws, _response) = connect_async(format!("ws://{addr}/ws")).await.unwrap();
    ws.send(WsMessage::Text(
        json!({ "type": "hello", "ticket": ticket, "protocol": 1 }).to_string(),
    ))
    .await
    .unwrap();
    let ack = read_frame(&mut ws).await;
    assert_eq!(ack["type"], "hello");
    ws
}

async fn read_frame(ws: &mut Client) -> Value {
    tokio::time::timeout(std::time::Duration::from_secs(2), async {
        loop {
            match ws.next().await {
                Some(Ok(WsMessage::Text(text))) => {
                    let frame: Value = serde_json::from_str(text.as_str()).unwrap();
                    if frame["type"] == "presence.changed" {
                        continue;
                    }
                    return frame;
                }
                Some(Ok(_)) => continue,
                other => panic!("expected a text frame, got {other:?}"),
            }
        }
    })
    .await
    .expect("timed out waiting for a frame")
}

fn put_slot_request(
    channel: ChannelId,
    token: &str,
    kind: &str,
    user_id: UserId,
    body: Value,
) -> Request<Body> {
    Request::builder()
        .method("PUT")
        .uri(format!(
            "/channels/{channel}/canvas/media-slots/{kind}/{user_id}"
        ))
        .header("authorization", format!("Bearer {token}"))
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

fn list_slots_request(channel: ChannelId, token: &str) -> Request<Body> {
    Request::builder()
        .method("GET")
        .uri(format!("/channels/{channel}/canvas/media-slots"))
        .header("authorization", format!("Bearer {token}"))
        .body(Body::empty())
        .unwrap()
}

fn screen_body(x: f64, y: f64) -> Value {
    json!({
        "x": x, "y": y, "w": 360.0, "h": 203.0,
        "locked": false, "sent_to_back": false,
    })
}

/// The owner's own scenario, verbatim: move a tile, then come back to a
/// *fresh* `Store` over the same database file - the shape a real restart
/// takes, not merely a second read against a process that never stopped.
#[tokio::test]
async fn persists_across_a_restart() {
    let (path, _guard) = support::TestDbGuard::new("slimm-media-slot-restart");
    let config = Config {
        port: 0,
        database_path: path.clone(),
        hash_concurrency: 2,
        ..Config::default()
    };
    let store = Store::new(db::connect(&config).await.unwrap());
    let (access, _ticket, alice) = user_ticket(&store, "alice").await;
    store.bootstrap_deployment(alice).await.unwrap();
    let channel = store.list_channels().await.unwrap()[0].id;

    let response = http::router(state_for(&store))
        .oneshot(put_slot_request(
            channel,
            &access,
            "screen",
            alice,
            screen_body(120.0, 340.0),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    // A new pool over the same file - nothing here is in-memory state, the same guarantee a restart needs.
    let restarted = Store::new(db::connect(&config).await.unwrap());
    let response = http::router(state_for(&restarted))
        .oneshot(list_slots_request(channel, &access))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: Value = serde_json::from_slice(&body).unwrap();
    let slots = json["slots"].as_array().unwrap();
    assert_eq!(slots.len(), 1);
    assert_eq!(slots[0]["kind"], "screen");
    assert_eq!(slots[0]["user_id"], alice.to_string());
    assert_eq!(slots[0]["x"], 120.0);
    assert_eq!(slots[0]["y"], 340.0);
}

/// The Figma precedent the owner invoked by name: any editor may drag any
/// sticky note. A slot names the participant it represents, not who
/// arranged it, so bob may move alice's own screen-share tile with nothing
/// beyond ordinary `USE_CANVAS`.
#[tokio::test]
async fn anyone_with_use_canvas_may_move_anyone_elses_slot() {
    let (path, _guard) = support::TestDbGuard::new("slimm-media-slot-anyone");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let store = Store::new(db::connect(&config).await.unwrap());
    let (_access, _ticket, alice) = user_ticket(&store, "alice").await;
    store.bootstrap_deployment(alice).await.unwrap();
    let channel = store.list_channels().await.unwrap()[0].id;
    let (bob_access, _bob_ticket, _bob) = user_ticket(&store, "bob").await;

    let response = http::router(state_for(&store))
        .oneshot(put_slot_request(
            channel,
            &bob_access,
            "screen",
            alice,
            screen_body(10.0, 20.0),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["user_id"], alice.to_string());
}

/// `USE_CANVAS` gates this route exactly as it gates a real object's move -
/// mutation-tested: dropping the permission check in
/// `http/canvas_media_slots.rs::upsert` fails exactly this test.
#[tokio::test]
async fn a_member_denied_use_canvas_is_forbidden() {
    let (path, _guard) = support::TestDbGuard::new("slimm-media-slot-denied");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let store = Store::new(db::connect(&config).await.unwrap());
    let (_access, _ticket, alice) = user_ticket(&store, "alice").await;
    store.bootstrap_deployment(alice).await.unwrap();
    let channel = store.list_channels().await.unwrap()[0].id;
    let (carol_access, _ticket, carol) = user_ticket(&store, "carol").await;
    store
        .set_member_overwrite(channel, carol, Permissions::NONE, Permissions::USE_CANVAS)
        .await
        .unwrap();

    let response = http::router(state_for(&store))
        .oneshot(put_slot_request(
            channel,
            &carol_access,
            "camera",
            carol,
            screen_body(0.0, 0.0),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

/// The write path's own direct timeout check, the same one
/// `placeCanvasObject` uses - mutation-tested: dropping `timed_out_until`
/// from `upsert` fails exactly this test.
#[tokio::test]
async fn a_timed_out_member_may_not_move_a_slot() {
    let (path, _guard) = support::TestDbGuard::new("slimm-media-slot-timeout");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let store = Store::new(db::connect(&config).await.unwrap());
    let (_access, _ticket, alice) = user_ticket(&store, "alice").await;
    store.bootstrap_deployment(alice).await.unwrap();
    let channel = store.list_channels().await.unwrap()[0].id;
    let (bob_access, _ticket, bob) = user_ticket(&store, "bob").await;
    store
        .set_member_timeout(bob, chrono_now_plus_ms(60_000), None, alice)
        .await
        .unwrap();

    let response = http::router(state_for(&store))
        .oneshot(put_slot_request(
            channel,
            &bob_access,
            "camera",
            bob,
            screen_body(0.0, 0.0),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

fn chrono_now_plus_ms(ms: i64) -> i64 {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as i64;
    now + ms
}

/// Every successful move publishes live, unconditionally - there is no
/// idempotency-by-id to dedupe against the way a placement has, so unlike
/// `placeCanvasObject` even a byte-identical repeat still fans out.
#[tokio::test]
async fn moving_a_slot_publishes_live_to_other_viewers() {
    let (path, _guard) = support::TestDbGuard::new("slimm-media-slot-live");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let store = Store::new(db::connect(&config).await.unwrap());
    let state = state_for(&store);
    let (access, _ticket, alice) = user_ticket(&store, "alice").await;
    store.bootstrap_deployment(alice).await.unwrap();
    let channel = store.list_channels().await.unwrap()[0].id;
    let (_bob_access, bob_ticket, _bob) = user_ticket(&store, "bob").await;

    let addr = serve(state.clone()).await;
    let mut bob_ws = connect(addr, &bob_ticket).await;

    let response = http::router(state.clone())
        .oneshot(put_slot_request(
            channel,
            &access,
            "camera",
            alice,
            screen_body(7.0, 8.0),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let frame = read_frame(&mut bob_ws).await;
    assert_eq!(frame["type"], "canvas.media_slot.changed");
    assert_eq!(frame["channel_id"], channel.to_string());
    assert_eq!(frame["kind"], "camera");
    assert_eq!(frame["user_id"], alice.to_string());
    assert_eq!(frame["x"], 7.0);
    assert_eq!(frame["y"], 8.0);
    assert_eq!(frame["locked"], false);
    assert_eq!(frame["sent_to_back"], false);
}

/// The concurrency question the reversal's own scope named directly: two
/// viewers racing to touch the same participant's slot for the first time
/// must not create two rows. Mutation-tested: replacing the upsert's
/// `ON CONFLICT ... DO UPDATE` with a plain `INSERT` in
/// `store/canvas_media_slots.rs` fails this test - the second of the two
/// concurrent calls errors on the table's own primary key instead of
/// overwriting the first.
#[tokio::test]
async fn two_concurrent_first_touches_leave_exactly_one_row() {
    let (path, _guard) = support::TestDbGuard::new("slimm-media-slot-race");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let store = Store::new(db::connect(&config).await.unwrap());
    let (access, _ticket, alice) = user_ticket(&store, "alice").await;
    store.bootstrap_deployment(alice).await.unwrap();
    let channel = store.list_channels().await.unwrap()[0].id;
    let state = state_for(&store);

    let first = http::router(state.clone()).oneshot(put_slot_request(
        channel,
        &access,
        "camera",
        alice,
        screen_body(1.0, 1.0),
    ));
    let second = http::router(state.clone()).oneshot(put_slot_request(
        channel,
        &access,
        "camera",
        alice,
        screen_body(2.0, 2.0),
    ));
    let (first, second) = tokio::join!(first, second);
    assert_eq!(first.unwrap().status(), StatusCode::OK);
    assert_eq!(second.unwrap().status(), StatusCode::OK);

    let slots = store.list_canvas_media_slots(channel).await.unwrap();
    assert_eq!(slots.len(), 1, "a race must not create two rows");
}

/// The same out-of-world check a placement already makes, applied here too:
/// a slot is not exempt from the bounded world just because it carries no
/// drawn content.
#[tokio::test]
async fn an_out_of_bounds_slot_is_refused() {
    let (path, _guard) = support::TestDbGuard::new("slimm-media-slot-bounds");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let store = Store::new(db::connect(&config).await.unwrap());
    let (access, _ticket, alice) = user_ticket(&store, "alice").await;
    store.bootstrap_deployment(alice).await.unwrap();
    let channel = store.list_channels().await.unwrap()[0].id;

    let response = http::router(state_for(&store))
        .oneshot(put_slot_request(
            channel,
            &access,
            "camera",
            alice,
            screen_body(50_000_000.0, 0.0),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

/// Account deletion removes a departed member's own slots outright, since a
/// slot names the participant it represents and there is nobody left to
/// name once that account is gone - mutation-tested: dropping the
/// `DELETE FROM canvas_media_slots` line in `account_deletion.rs` fails
/// exactly this test.
#[tokio::test]
async fn deleting_an_account_removes_its_slots() {
    let (path, _guard) = support::TestDbGuard::new("slimm-media-slot-deletion");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let store = Store::new(db::connect(&config).await.unwrap());
    let (_access, _ticket, alice) = user_ticket(&store, "alice").await;
    store.bootstrap_deployment(alice).await.unwrap();
    let channel = store.list_channels().await.unwrap()[0].id;
    let (_bob_access, _bob_ticket, bob) = user_ticket(&store, "bob").await;

    store
        .upsert_canvas_media_slot(
            channel,
            bob,
            slimm_server::store::MediaSlotKind::Camera,
            (0.0, 0.0, 140.0, 140.0),
            false,
            false,
        )
        .await
        .unwrap();
    assert_eq!(
        store.list_canvas_media_slots(channel).await.unwrap().len(),
        1
    );

    store.delete_account(bob).await.unwrap();

    assert_eq!(
        store.list_canvas_media_slots(channel).await.unwrap().len(),
        0
    );
}
