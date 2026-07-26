// SPDX-License-Identifier: AGPL-3.0-only
//! End-to-end WebSocket tests against a real server on an ephemeral port, driven
//! by a real WebSocket client. Covers the two-client fan-out and ordering, the
//! per-event permission filter, and connect-time ticket auth.

use std::time::Duration;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use futures_util::{SinkExt, StreamExt};
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
use tokio::net::TcpListener;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tower::ServiceExt;
use uuid::Uuid;

type Client =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn new_store() -> Store {
    let path = std::env::temp_dir()
        .join(format!("slimm-ws-test-{}.db", uuid::Uuid::now_v7()))
        .to_string_lossy()
        .into_owned();
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    Store::new(pool)
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
    let store = new_store().await;
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
    let store = new_store().await;
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

#[tokio::test]
async fn logout_closes_the_live_socket() {
    let store = new_store().await;
    let state = state_for(&store);
    let (alice_access, alice_ticket, _alice) = user_ticket(&store, "alice").await;

    let addr = serve(state.clone()).await;
    let mut alice_ws = connect(addr, &alice_ticket).await;

    // Log out over REST on the same session; the shared hub carries the
    // revocation to the live socket.
    let response = http::router(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/auth/logout")
                .header("authorization", format!("Bearer {alice_access}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    // The socket closes promptly rather than lingering with fan-out access.
    let closed = tokio::time::timeout(Duration::from_secs(2), wait_closed(&mut alice_ws)).await;
    assert!(closed.is_ok(), "the socket should close after logout");
}

#[tokio::test]
async fn a_bad_ticket_is_rejected() {
    let store = new_store().await;
    let addr = serve(state_for(&store)).await;

    let (mut ws, _response) = connect_async(format!("ws://{addr}/ws")).await.unwrap();
    ws.send(WsMessage::Text(
        json!({ "type": "hello", "ticket": "not-a-real-ticket", "protocol": 1 }).to_string(),
    ))
    .await
    .unwrap();

    let frame = read_frame(&mut ws).await;
    assert_eq!(frame["type"], "error");
}

/// Deleting an account revokes its sessions and publishes the same event
/// logout does, but only logout had a test proving a live socket actually
/// closes. Deletion is the path where a socket left attached would keep
/// delivering a channel's messages to an account that no longer exists.
#[tokio::test]
async fn deleting_the_account_closes_its_live_socket() {
    let store = new_store().await;
    let state = state_for(&store);
    let (alice_access, alice_ticket, _alice) = user_ticket(&store, "alice").await;

    let addr = serve(state.clone()).await;
    let mut alice_ws = connect(addr, &alice_ticket).await;

    let response = http::router(state.clone())
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri("/account")
                .header("authorization", format!("Bearer {alice_access}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    let closed = tokio::time::timeout(Duration::from_secs(2), wait_closed(&mut alice_ws)).await;
    assert!(
        closed.is_ok(),
        "the socket must close when the account behind it is deleted"
    );
}
