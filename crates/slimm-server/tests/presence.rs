// SPDX-License-Identifier: AGPL-3.0-only
//! End-to-end presence tests: the appear-offline leak test (through both the
//! REST batch lookup and the WebSocket broadcast), and that presence flips to
//! offline when the last live socket closes rather than only when a client
//! says so.

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

async fn new_store() -> (Store, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new("slimm-presence-test");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    (Store::new(pool), guard)
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
    loop {
        match ws.next().await {
            Some(Ok(WsMessage::Text(text))) => {
                return serde_json::from_str(text.as_str()).unwrap();
            }
            Some(Ok(_)) => continue,
            other => panic!("expected a text frame, got {other:?}"),
        }
    }
}

/// Reads frames until one is a `presence.changed` for `user_id`, ignoring any
/// other event kind. Bounded so a missing event fails the test instead of
/// hanging it.
async fn next_presence_for(ws: &mut Client, user_id: &str) -> Value {
    let outcome = tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            let frame = read_frame(ws).await;
            if frame["type"] == "presence.changed" && frame["user_id"] == user_id {
                return frame;
            }
        }
    })
    .await;
    outcome.unwrap_or_else(|_| panic!("no presence.changed for {user_id} arrived in time"))
}

fn get_request(uri: &str, token: &str) -> Request<Body> {
    Request::builder()
        .method("GET")
        .uri(uri)
        .header("authorization", format!("Bearer {token}"))
        .body(Body::empty())
        .unwrap()
}

fn patch_request(uri: &str, token: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method("PATCH")
        .uri(uri)
        .header("authorization", format!("Bearer {token}"))
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

async fn presence_status(state: &AppState, token: &str, target_id: &str) -> String {
    let uri = format!("/presence?ids={target_id}");
    let response = http::router(state.clone())
        .oneshot(get_request(&uri, token))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let entries: Vec<Value> = serde_json::from_slice(&body).unwrap();
    entries[0]["status"].as_str().unwrap().to_owned()
}

/// A hidden user reads as offline to another user, but their own client still
/// sees their true (connected, online) state, through both the REST batch
/// lookup and the WebSocket broadcast. This is the appear-offline leak test:
/// the same underlying event and the same REST query, answered differently
/// only because the viewer differs.
#[tokio::test]
async fn hidden_user_reads_offline_to_others_but_true_to_self() {
    let (store, _guard) = new_store().await;
    let state = state_for(&store);
    let (alice_access, alice_ticket, alice_id) = user_ticket(&store, "alice").await;
    let (_bob_access, bob_ticket, _bob_id) = user_ticket(&store, "bob").await;
    let alice_id_str = alice_id.to_string();

    let addr = serve(state.clone()).await;

    // Bob connects first so he is already subscribed when alice's connect
    // (and later her visibility change) publishes.
    let mut bob_ws = connect(addr, &bob_ticket).await;
    // Bob's own connect published his own presence; drain it before looking
    // for alice's.
    let bob_self = next_presence_for(&mut bob_ws, &_bob_id.to_string()).await;
    assert_eq!(bob_self["status"], "online");

    let mut alice_ws = connect(addr, &alice_ticket).await;

    // Alice's own connection sees her true state immediately on connect.
    let alice_self = next_presence_for(&mut alice_ws, &alice_id_str).await;
    assert_eq!(alice_self["status"], "online");
    // Bob, a different viewer, sees the same default-visibility online state.
    let bob_view = next_presence_for(&mut bob_ws, &alice_id_str).await;
    assert_eq!(bob_view["status"], "online");

    // Alice sets appear-offline over REST.
    let response = http::router(state.clone())
        .oneshot(patch_request(
            "/presence",
            &alice_access,
            json!({ "visibility": "hidden" }),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    // Alice's own live connection still reports her true state: connected,
    // so online, never forced offline for herself.
    let alice_self_after = next_presence_for(&mut alice_ws, &alice_id_str).await;
    assert_eq!(
        alice_self_after["status"], "online",
        "a hidden user's own client sees their true state"
    );
    // Bob sees her as offline, even though she is still fully connected.
    let bob_view_after = next_presence_for(&mut bob_ws, &alice_id_str).await;
    assert_eq!(
        bob_view_after["status"], "offline",
        "everyone else sees a hidden user as offline"
    );

    // The same asymmetry holds over the REST batch lookup, not just the socket.
    assert_eq!(
        presence_status(&state, &alice_access, &alice_id_str).await,
        "online"
    );
    assert_eq!(
        presence_status(&state, &_bob_access, &alice_id_str).await,
        "offline"
    );
}

/// Presence flips to offline when the last socket closes, not merely when a
/// client says so: this closes the connection abruptly (a plain drop) rather
/// than sending any "I am offline now" message, and confirms both a watching
/// peer and the REST surface observe the transition.
#[tokio::test]
async fn presence_flips_to_offline_when_the_last_socket_closes() {
    let (store, _guard) = new_store().await;
    let state = state_for(&store);
    let (_alice_access, alice_ticket, alice_id) = user_ticket(&store, "alice").await;
    let (bob_access, bob_ticket, _bob_id) = user_ticket(&store, "bob").await;
    let alice_id_str = alice_id.to_string();

    let addr = serve(state.clone()).await;
    let mut bob_ws = connect(addr, &bob_ticket).await;
    let _ = next_presence_for(&mut bob_ws, &_bob_id.to_string()).await;

    let alice_ws = connect(addr, &alice_ticket).await;
    let online = next_presence_for(&mut bob_ws, &alice_id_str).await;
    assert_eq!(online["status"], "online");
    assert_eq!(
        presence_status(&state, &bob_access, &alice_id_str).await,
        "online"
    );

    // Abruptly drop alice's connection: no logout, no "going offline" frame,
    // just the socket disappearing, the way a crash or a lost network would.
    drop(alice_ws);

    let offline = next_presence_for(&mut bob_ws, &alice_id_str).await;
    assert_eq!(offline["status"], "offline");

    // Give the server a moment to finish the disconnect bookkeeping the
    // dropped socket triggered, then confirm REST agrees too.
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(
        presence_status(&state, &bob_access, &alice_id_str).await,
        "offline"
    );
}

/// A user missing from the batch lookup (never existed) is simply absent,
/// the same contract `GET /users` has, rather than an error or a synthesized
/// "offline" entry.
#[tokio::test]
async fn unknown_id_is_simply_absent() {
    let (store, _guard) = new_store().await;
    let state = state_for(&store);
    let (access, _ticket, _id) = user_ticket(&store, "alice").await;

    let missing = uuid::Uuid::now_v7();
    let response = http::router(state.clone())
        .oneshot(get_request(&format!("/presence?ids={missing}"), &access))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let entries: Vec<Value> = serde_json::from_slice(&body).unwrap();
    assert!(entries.is_empty());
}
