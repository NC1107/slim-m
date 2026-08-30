// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! End-to-end WebSocket tests against a real server on an ephemeral port, driven
//! by a real WebSocket client. Covers the two-client fan-out and ordering and
//! the per-event permission filter, including a store error while resolving
//! it. Session-lifecycle closes (logout, device removal, account deletion, a
//! bad ticket) live in `tests/ws_session_lifecycle.rs`.

use std::time::Duration;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use futures_util::{SinkExt, StreamExt};
use serde_json::{Value, json};
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::{Event, Hub};
use slimm_server::ids::MessageId;
use slimm_server::permissions::Permissions;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use sqlx::SqlitePool;
use tokio::net::TcpListener;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tower::ServiceExt;
use uuid::Uuid;

mod support;

type Client =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn new_store() -> (Store, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new("slimm-ws-test");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    (Store::new(pool), guard)
}

/// Like [`new_store`], but also hands back the raw pool so a test can break a
/// single query for real; see
/// `a_store_error_authorizing_fan_out_closes_the_connection`.
async fn new_store_with_pool() -> (Store, SqlitePool, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new("slimm-ws-test");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    (Store::new(pool.clone()), pool, guard)
}

fn state_for(store: &Store) -> AppState {
    AppState {
        store: store.clone(),
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: slimm_server::voice::VoiceService::disabled(),
        media: slimm_server::media::Media::for_tests(),
        gifs: slimm_server::http::gifs::GifSearch::disabled(),
    }
}

/// Creates a user and returns (rest access token, ws connect ticket, user id).
async fn user_ticket(store: &Store, name: &str) -> (String, String, slimm_server::ids::UserId) {
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

/// Spawns the real server and returns its address.
async fn serve(state: AppState) -> std::net::SocketAddr {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, http::router(state)).await.unwrap();
    });
    addr
}

/// Connects, performs the hello handshake, and returns the live socket.
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

/// Reads the next text frame as JSON, skipping any control frames.
///
/// Also skips `presence.changed`: every connect and disconnect in this file
/// publishes one on the same shared hub these tests assert against, so with
/// two or more live sockets it is real, expected chatter rather than
/// something any test here is checking. Presence has its own dedicated
/// coverage in `tests/presence.rs`.
async fn read_frame(ws: &mut Client) -> Value {
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
}

/// Resolves once the socket has closed (a close frame, end of stream, or error).
async fn wait_closed(ws: &mut Client) {
    loop {
        match ws.next().await {
            None | Some(Ok(WsMessage::Close(_))) | Some(Err(_)) => return,
            Some(Ok(_)) => continue,
        }
    }
}

fn send_request(uri: &str, token: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri(uri)
        .header("authorization", format!("Bearer {token}"))
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

#[tokio::test]
async fn two_clients_receive_fan_out_in_order() {
    let (store, _guard) = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES),
            true,
        )
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let state = state_for(&store);

    let (alice_access, alice_ticket, _alice) = user_ticket(&store, "alice").await;
    let (_bob_access, bob_ticket, _bob) = user_ticket(&store, "bob").await;

    let addr = serve(state.clone()).await;
    let mut alice_ws = connect(addr, &alice_ticket).await;
    let mut bob_ws = connect(addr, &bob_ticket).await;

    // A REST send on a router sharing the same hub reaches both connections.
    let uri = format!("/channels/{}/messages", channel.id);
    let response = http::router(state.clone())
        .oneshot(send_request(
            &uri,
            &alice_access,
            json!({ "id": Uuid::now_v7().to_string(), "content": "hello everyone" }),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    for ws in [&mut alice_ws, &mut bob_ws] {
        let frame = read_frame(ws).await;
        assert_eq!(frame["type"], "message.created");
        assert_eq!(frame["seq"], 1);
        assert_eq!(frame["message"]["content"], "hello everyone");
    }
}

#[tokio::test]
async fn fan_out_respects_view_permission() {
    let (store, _guard) = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES),
            true,
        )
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let state = state_for(&store);

    let (alice_access, alice_ticket, _alice) = user_ticket(&store, "alice").await;
    let (_bob_access, bob_ticket, bob) = user_ticket(&store, "bob").await;

    // Deny bob the view of this channel specifically.
    store
        .set_member_overwrite(
            channel.id,
            bob,
            Permissions::NONE,
            Permissions::VIEW_CHANNEL,
        )
        .await
        .unwrap();

    let addr = serve(state.clone()).await;
    let mut alice_ws = connect(addr, &alice_ticket).await;
    let mut bob_ws = connect(addr, &bob_ticket).await;

    let uri = format!("/channels/{}/messages", channel.id);
    http::router(state.clone())
        .oneshot(send_request(
            &uri,
            &alice_access,
            json!({ "id": Uuid::now_v7().to_string(), "content": "members only" }),
        ))
        .await
        .unwrap();

    // Alice, who can view, receives it.
    let frame = read_frame(&mut alice_ws).await;
    assert_eq!(frame["type"], "message.created");

    // Bob, denied view of this channel, receives nothing within a short window.
    let bob_next = tokio::time::timeout(Duration::from_millis(300), read_frame(&mut bob_ws)).await;
    assert!(bob_next.is_err(), "bob must not receive a hidden channel");
}

/// A store error while resolving the fan-out permission check must not read
/// as "not visible" and be silently dropped: `/sync` filters purely by seq,
/// so a connection whose cursor has already moved past a dropped event can
/// never recover it short of a full channel reset. The connection closes
/// instead, onto the same resync path a lagged subscriber already takes.
///
/// The message is sent through `Store::send_message` directly rather than the
/// REST handler, and the column is broken before that call rather than after:
/// the REST handler's own permission check reads the identical query, so
/// breaking it first (rather than racing the handler's send against the
/// asynchronous fan-out) is what makes this deterministic instead of racy.
#[tokio::test]
async fn a_store_error_authorizing_fan_out_closes_the_connection() {
    let (store, pool, _guard) = new_store_with_pool().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES),
            true,
        )
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let state = state_for(&store);

    let (_alice_access, _alice_ticket, alice) = user_ticket(&store, "alice").await;
    let (_bob_access, bob_ticket, _bob) = user_ticket(&store, "bob").await;

    let addr = serve(state.clone()).await;
    let mut bob_ws = connect(addr, &bob_ticket).await;

    sqlx::query("ALTER TABLE channels RENAME COLUMN topic TO topic_broken")
        .execute(&pool)
        .await
        .expect("break the column permissions_in_channel queries by name");

    let sent = store
        .send_message(channel.id, alice, MessageId::generate(), "hello", &[], None)
        .await
        .unwrap();
    state.hub.publish(Event::MessageCreated {
        message: sent.message,
        attachments: Vec::new(),
    });

    let closed = tokio::time::timeout(Duration::from_secs(2), wait_closed(&mut bob_ws)).await;
    assert!(
        closed.is_ok(),
        "a store error authorizing fan-out must close the connection, not drop the message"
    );
}

/// A brand new message can already carry an attachment, and the live frame is
/// the only thing a connected client sees until its next sync.
///
/// The frame used to be built from a bare row, which cannot express one, so an
/// image arrived as an empty message and only gained its picture on reconnect.
#[tokio::test]
async fn a_live_frame_carries_the_attachment_the_message_was_sent_with() {
    let (store, _guard) = new_store().await;
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL
                .union(Permissions::SEND_MESSAGES)
                .union(Permissions::ATTACH_FILES),
            true,
        )
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let state = state_for(&store);

    let (alice_access, _alice_ticket, alice_id) = user_ticket(&store, "alice").await;
    let (_bob_access, bob_ticket, _bob) = user_ticket(&store, "bob").await;

    // Stored directly: this test is about the fan-out, not the upload route.
    // The id on the wire is the lowercase hex of the content hash.
    // 32 bytes: the id is a sha256, and a short one is refused as malformed.
    let bytes = [0x11u8; 32];
    store
        .store_attachment(
            &bytes,
            bytes.len() as i64,
            "image/png",
            "shot.png",
            Some(alice_id),
        )
        .await
        .unwrap();
    let attachment_id: String = bytes.iter().map(|b| format!("{b:02x}")).collect();

    let addr = serve(state.clone()).await;
    let mut bob_ws = connect(addr, &bob_ticket).await;

    let uri = format!("/channels/{}/messages", channel.id);
    let response = http::router(state.clone())
        .oneshot(send_request(
            &uri,
            &alice_access,
            json!({
                "id": Uuid::now_v7().to_string(),
                "content": "look at this",
                "attachment_ids": [attachment_id],
            }),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let frame = read_frame(&mut bob_ws).await;
    assert_eq!(frame["type"], "message.created");
    let attachments = frame["message"]["attachments"]
        .as_array()
        .expect("the frame carries an attachments array");
    assert_eq!(
        attachments.len(),
        1,
        "the live frame must carry the attachment, not leave it for the next sync: {frame}"
    );
    assert_eq!(attachments[0]["filename"], "shot.png");
    assert_eq!(attachments[0]["content_type"], "image/png");
}
