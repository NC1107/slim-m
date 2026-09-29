// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! `POST /channels/{id}/ephemeral-messages`: a bot's private answer reaches
//! exactly one member's sockets and leaves no trace anywhere else.
//! See docs/decisions/0037-ephemeral-bot-messages.md.

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
use slimm_server::ids::{ChannelId, UserId};
use slimm_server::permissions::Permissions;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use tokio::net::TcpListener;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message as WsMessage;
use tower::ServiceExt;
use uuid::Uuid;

mod support;

type Client =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

struct World {
    state: AppState,
    pool: sqlx::SqlitePool,
    channel: ChannelId,
    admin: (UserId, String),
    alice: (UserId, String),
    bob: (UserId, String),
    bot: (UserId, String),
    _guard: support::TestDbGuard,
}

async fn world() -> World {
    let (path, guard) = support::TestDbGuard::new("slimm-ephemeral");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    let store = Store::new(pool.clone());
    let root = store
        .create_account("root", "root", "not-a-real-hash")
        .await
        .unwrap();
    store.bootstrap_deployment(root.id).await.unwrap();
    let channel = store.create_channel("general", "text").await.unwrap().id;
    let admin_token = store
        .open_session(root.id, "cli")
        .await
        .unwrap()
        .access_token;
    let mut members = Vec::new();
    for name in ["alice", "bob"] {
        let user = store.create_user(name, name).await.unwrap();
        let token = store
            .open_session(user.id, "cli")
            .await
            .unwrap()
            .access_token;
        members.push((user.id, token));
    }
    let bot = store
        .create_bot("helper", "Helper", Permissions::NONE, root.id)
        .await
        .unwrap();
    let state = AppState {
        store,
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: slimm_server::voice::VoiceService::disabled(),
        media: slimm_server::media::Media::for_tests(),
        gifs: slimm_server::http::gifs::GifSearch::disabled(),
        link_previews: slimm_server::http::link_preview::LinkPreviews::disabled(),
        dock: slimm_server::http::dock::Dock::disabled(),
        code_runner: slimm_server::code_runner::CodeRunner::disabled(),
    };
    World {
        state,
        pool,
        channel,
        admin: (root.id, admin_token),
        alice: members.remove(0),
        bob: members.remove(0),
        bot: (bot.bot.user_id, bot.token),
        _guard: guard,
    }
}

fn request(method: &str, uri: &str, token: &str, body: Option<Value>) -> Request<Body> {
    let builder = Request::builder()
        .method(method)
        .uri(uri)
        .header("authorization", format!("Bearer {token}"));
    match body {
        Some(value) => builder
            .header("content-type", "application/json")
            .body(Body::from(value.to_string()))
            .unwrap(),
        None => builder.body(Body::empty()).unwrap(),
    }
}

async fn call(
    w: &World,
    method: &str,
    uri: &str,
    token: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let response = http::router(w.state.clone())
        .oneshot(request(method, uri, token, body))
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

async fn say(w: &World, token: &str, channel: ChannelId, text: &str) -> Value {
    let (status, body) = call(
        w,
        "POST",
        &format!("/channels/{channel}/messages"),
        token,
        Some(json!({ "id": Uuid::now_v7().to_string(), "content": text })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    body
}

async fn whisper(
    w: &World,
    token: &str,
    channel: ChannelId,
    anchor: &Value,
    text: &str,
) -> (StatusCode, Value) {
    call(
        w,
        "POST",
        &format!("/channels/{channel}/ephemeral-messages"),
        token,
        Some(json!({ "in_reply_to_id": anchor["id"], "content": text })),
    )
    .await
}

async fn connect(w: &World, addr: std::net::SocketAddr, token: &str) -> Client {
    let (status, minted) = call(w, "POST", "/auth/ws-ticket", token, Some(json!({}))).await;
    assert_eq!(status, StatusCode::OK);
    let ticket = minted["ticket"].as_str().unwrap().to_owned();
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
                let frame: Value = serde_json::from_str(text.as_str()).unwrap();
                if frame["type"] != "presence.changed" {
                    return frame;
                }
            }
            Some(Ok(_)) => continue,
            other => panic!("expected a text frame, got {other:?}"),
        }
    }
}

async fn frame_of_kind(ws: &mut Client, kind: &str) -> Option<Value> {
    while let Ok(frame) = tokio::time::timeout(Duration::from_millis(400), read_frame(ws)).await {
        if frame["type"] == kind {
            return Some(frame);
        }
    }
    None
}

async fn serve(state: AppState) -> std::net::SocketAddr {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, http::router(state)).await.unwrap();
    });
    addr
}

#[tokio::test]
async fn only_the_addressed_members_own_sockets_hear_it() {
    let w = world().await;
    let anchor = say(&w, &w.alice.1, w.channel, "!balance").await;
    let addr = serve(w.state.clone()).await;
    let mut phone = connect(&w, addr, &w.alice.1).await;
    let mut desktop = connect(&w, addr, &w.alice.1).await;
    let mut bob = connect(&w, addr, &w.bob.1).await;
    let mut admin = connect(&w, addr, &w.admin.1).await;
    let mut bot = connect(&w, addr, &w.bot.1).await;

    let (status, sent) = whisper(&w, &w.bot.1, w.channel, &anchor, "you have 500 chips").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(sent["author_id"], w.bot.0.to_string());
    assert_eq!(sent["in_reply_to_id"], anchor["id"]);
    assert!(sent.get("seq").is_none(), "it must carry no seq");

    for ws in [&mut phone, &mut desktop] {
        let frame = frame_of_kind(ws, "message.ephemeral")
            .await
            .expect("every device of the addressed member must hear it");
        assert_eq!(frame["message"]["content"], "you have 500 chips");
        assert_eq!(frame["message"]["id"], sent["id"]);
    }
    for (who, ws) in [
        ("bob", &mut bob),
        ("an administrator", &mut admin),
        ("the bot", &mut bot),
    ] {
        assert!(
            frame_of_kind(ws, "message.ephemeral").await.is_none(),
            "{who} must not hear a private message"
        );
    }
}

#[tokio::test]
async fn it_leaves_no_trace_in_history_search_sync_or_seq() {
    let w = world().await;
    let first = say(&w, &w.alice.1, w.channel, "!balance").await;
    assert_eq!(first["seq"], 1);
    let (status, _) = whisper(&w, &w.bot.1, w.channel, &first, "zebrafruit secret").await;
    assert_eq!(status, StatusCode::OK);
    let second = say(&w, &w.bob.1, w.channel, "hello").await;
    assert_eq!(second["seq"], 2, "a private message must leave no gap");

    for token in [&w.alice.1, &w.bob.1, &w.admin.1] {
        let uri = format!("/channels/{}/messages", w.channel);
        let (_, page) = call(&w, "GET", &uri, token, None).await;
        assert!(!page.to_string().contains("zebrafruit"));
        let (_, found) = call(&w, "GET", "/search/messages?q=zebrafruit", token, None).await;
        assert!(!found.to_string().contains("zebrafruit"));
        let scopes = json!({ "scopes": [{ "channel_id": w.channel.to_string(), "after_seq": 0 }] });
        let (_, synced) = call(&w, "POST", "/sync", token, Some(scopes)).await;
        assert!(!synced.to_string().contains("zebrafruit"));
        assert_eq!(synced["scopes"][0]["messages"].as_array().unwrap().len(), 2);
    }
}

#[tokio::test]
async fn a_member_cannot_send_one() {
    let w = world().await;
    let anchor = say(&w, &w.alice.1, w.channel, "hi").await;
    let (status, _) = whisper(&w, &w.bob.1, w.channel, &anchor, "boo").await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = whisper(&w, &w.admin.1, w.channel, &anchor, "boo").await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn the_recipient_is_the_anchors_author_and_nobody_else() {
    let w = world().await;
    let other = w
        .state
        .store
        .create_channel("random", "text")
        .await
        .unwrap()
        .id;
    let elsewhere = say(&w, &w.alice.1, other, "hi").await;
    let (status, _) = whisper(&w, &w.bot.1, w.channel, &elsewhere, "x").await;
    assert_eq!(
        status,
        StatusCode::NOT_FOUND,
        "an anchor in another channel"
    );

    let unknown = json!({ "id": Uuid::now_v7().to_string() });
    let (status, _) = whisper(&w, &w.bot.1, w.channel, &unknown, "x").await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let own = say(&w, &w.bot.1, w.channel, "public").await;
    let (status, _) = whisper(&w, &w.bot.1, w.channel, &own, "x").await;
    assert_eq!(
        status,
        StatusCode::FORBIDDEN,
        "a bot's own message is no anchor"
    );
}

#[tokio::test]
async fn an_old_message_is_no_longer_an_anchor() {
    let w = world().await;
    let anchor = say(&w, &w.alice.1, w.channel, "!balance").await;
    sqlx::query("UPDATE messages SET created_at = created_at - ? WHERE id = ?")
        .bind(slimm_server::ephemeral::ANCHOR_WINDOW_MS + 60_000)
        .bind(Uuid::parse_str(anchor["id"].as_str().unwrap()).unwrap())
        .execute(&w.pool)
        .await
        .unwrap();
    let (status, _) = whisper(&w, &w.bot.1, w.channel, &anchor, "late").await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn a_recipient_who_can_no_longer_view_the_channel_is_refused() {
    let w = world().await;
    let anchor = say(&w, &w.alice.1, w.channel, "!balance").await;
    w.state
        .store
        .set_member_overwrite(
            w.channel,
            w.alice.0,
            Permissions::NONE,
            Permissions::VIEW_CHANNEL,
        )
        .await
        .unwrap();
    let (status, _) = whisper(&w, &w.bot.1, w.channel, &anchor, "x").await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn content_is_validated_like_a_message() {
    let w = world().await;
    let anchor = say(&w, &w.alice.1, w.channel, "hi").await;
    let (status, _) = whisper(&w, &w.bot.1, w.channel, &anchor, "   ").await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _) = whisper(&w, &w.bot.1, w.channel, &anchor, &"x".repeat(4_001)).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn a_member_who_blocked_the_bot_never_hears_it() {
    let w = world().await;
    let anchor = say(&w, &w.alice.1, w.channel, "hi").await;
    w.state.store.block_user(w.alice.0, w.bot.0).await.unwrap();
    let addr = serve(w.state.clone()).await;
    let mut alice = connect(&w, addr, &w.alice.1).await;
    let (status, _) = whisper(&w, &w.bot.1, w.channel, &anchor, "x").await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        frame_of_kind(&mut alice, "message.ephemeral")
            .await
            .is_none()
    );
}
