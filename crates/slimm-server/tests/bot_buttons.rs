// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Buttons on a bot's message, the click that reaches only that bot, and the
//! private answer that reaches only the clicker.
//! See docs/decisions/0038-bot-message-buttons.md.

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
    channel: ChannelId,
    alice: (UserId, String),
    bob: (UserId, String),
    bot: (UserId, String),
    other_bot: (UserId, String),
    _guard: support::TestDbGuard,
}

async fn world() -> World {
    let (path, guard) = support::TestDbGuard::new("slimm-buttons");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    let store = Store::new(pool);
    let root = store
        .create_account("root", "root", "not-a-real-hash")
        .await
        .unwrap();
    store.bootstrap_deployment(root.id).await.unwrap();
    let channel = store.create_channel("general", "text").await.unwrap().id;
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
    let mut bots = Vec::new();
    for name in ["helper", "rival"] {
        let bot = store
            .create_bot(name, name, Permissions::NONE, root.id)
            .await
            .unwrap();
        bots.push((bot.bot.user_id, bot.token));
    }
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
        channel,
        alice: members.remove(0),
        bob: members.remove(0),
        bot: bots.remove(0),
        other_bot: bots.remove(0),
        _guard: guard,
    }
}

async fn call(
    w: &World,
    method: &str,
    uri: &str,
    token: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let builder = Request::builder()
        .method(method)
        .uri(uri)
        .header("authorization", format!("Bearer {token}"));
    let request = match body {
        Some(value) => builder
            .header("content-type", "application/json")
            .body(Body::from(value.to_string()))
            .unwrap(),
        None => builder.body(Body::empty()).unwrap(),
    };
    let response = http::router(w.state.clone())
        .oneshot(request)
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

fn buttons() -> Value {
    json!([{ "buttons": [
        { "label": "Hit", "style": "primary", "custom_id": "hit" },
        { "label": "Stand", "style": "secondary", "custom_id": "stand" },
        { "label": "Rules", "style": "link", "url": "https://example.com/rules" }
    ]}])
}

async fn post_with(w: &World, token: &str, components: Value) -> (StatusCode, Value) {
    call(
        w,
        "POST",
        &format!("/channels/{}/messages", w.channel),
        token,
        Some(json!({
            "id": Uuid::now_v7().to_string(),
            "content": "your move",
            "components": components,
        })),
    )
    .await
}

async fn posted(w: &World) -> Value {
    let (status, message) = post_with(w, &w.bot.1, buttons()).await;
    assert_eq!(status, StatusCode::OK);
    message
}

async fn press(
    w: &World,
    token: &str,
    message: &Value,
    custom_id: &str,
) -> (StatusCode, Value, String) {
    let id = Uuid::now_v7().to_string();
    let (status, body) = call(
        w,
        "POST",
        &format!(
            "/channels/{}/messages/{}/interactions",
            w.channel,
            message["id"].as_str().unwrap()
        ),
        token,
        Some(json!({ "id": id, "custom_id": custom_id })),
    )
    .await;
    (status, body, id)
}

async fn whisper(w: &World, token: &str, anchor: &str, text: &str) -> StatusCode {
    call(
        w,
        "POST",
        &format!("/channels/{}/ephemeral-messages", w.channel),
        token,
        Some(json!({ "in_reply_to_id": anchor, "content": text })),
    )
    .await
    .0
}

async fn connect(w: &World, addr: std::net::SocketAddr, token: &str) -> Client {
    let (_, minted) = call(w, "POST", "/auth/ws-ticket", token, Some(json!({}))).await;
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
async fn buttons_ride_send_list_and_sync_and_only_a_bot_may_post_them() {
    let w = world().await;
    let sent = posted(&w).await;
    assert_eq!(sent["components"][0]["buttons"][1]["custom_id"], "stand");

    let uri = format!("/channels/{}/messages", w.channel);
    let (_, page) = call(&w, "GET", &uri, &w.alice.1, None).await;
    assert_eq!(page[0]["components"], sent["components"]);
    let scopes = json!({ "scopes": [{ "channel_id": w.channel.to_string(), "after_seq": 0 }] });
    let (_, synced) = call(&w, "POST", "/sync", &w.alice.1, Some(scopes)).await;
    assert_eq!(
        synced["scopes"][0]["messages"][0]["components"],
        sent["components"]
    );

    let (status, _) = post_with(&w, &w.alice.1, buttons()).await;
    assert_eq!(
        status,
        StatusCode::FORBIDDEN,
        "a member cannot post buttons"
    );
}

#[tokio::test]
async fn the_live_frame_and_an_edit_keep_the_buttons() {
    let w = world().await;
    let addr = serve(w.state.clone()).await;
    let mut alice = connect(&w, addr, &w.alice.1).await;
    let sent = posted(&w).await;
    let created = frame_of_kind(&mut alice, "message.created").await.unwrap();
    assert_eq!(created["message"]["components"], sent["components"]);

    let uri = format!(
        "/channels/{}/messages/{}",
        w.channel,
        sent["id"].as_str().unwrap()
    );
    let (status, _) = call(
        &w,
        "PATCH",
        &uri,
        &w.bot.1,
        Some(json!({ "content": "new text" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, page) = call(
        &w,
        "GET",
        &format!("/channels/{}/messages", w.channel),
        &w.alice.1,
        None,
    )
    .await;
    assert_eq!(page[0]["content"], "new text");
    assert_eq!(
        page[0]["components"], sent["components"],
        "an edit must not drop the buttons"
    );
}

#[tokio::test]
async fn the_caps_are_enforced() {
    let w = world().await;
    let six_rows: Vec<Value> = (0..6)
        .map(|r| json!({ "buttons": [{ "label": "x", "style": "primary", "custom_id": format!("r{r}") }] }))
        .collect();
    let six_wide = json!([{ "buttons": (0..6)
        .map(|c| json!({ "label": "x", "style": "primary", "custom_id": format!("c{c}") }))
        .collect::<Vec<_>>() }]);
    let long_label =
        json!([{ "buttons": [{ "label": "x".repeat(81), "style": "primary", "custom_id": "a" }] }]);
    let long_id = json!([{ "buttons": [{ "label": "x", "style": "primary", "custom_id": "i".repeat(101) }] }]);
    let bad_link =
        json!([{ "buttons": [{ "label": "x", "style": "link", "url": "javascript:alert(1)" }] }]);
    for bad in [json!(six_rows), six_wide, long_label, long_id, bad_link] {
        let (status, _) = post_with(&w, &w.bot.1, bad).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
    }
}

#[tokio::test]
async fn a_press_reaches_only_the_owning_bot_and_a_retry_is_the_same_press() {
    let w = world().await;
    let sent = posted(&w).await;
    let addr = serve(w.state.clone()).await;
    let mut bot = connect(&w, addr, &w.bot.1).await;
    let mut rival = connect(&w, addr, &w.other_bot.1).await;
    let mut bob = connect(&w, addr, &w.bob.1).await;

    let (status, _, id) = press(&w, &w.alice.1, &sent, "hit").await;
    assert_eq!(status, StatusCode::OK);
    let frame = frame_of_kind(&mut bot, "interaction.created")
        .await
        .expect("the owning bot hears it");
    assert_eq!(frame["interaction_id"], id);
    assert_eq!(frame["custom_id"], "hit");
    assert_eq!(frame["user_id"], w.alice.0.to_string());
    assert_eq!(frame["message_id"], sent["id"]);
    for (who, ws) in [("another bot", &mut rival), ("another member", &mut bob)] {
        assert!(
            frame_of_kind(ws, "interaction.created").await.is_none(),
            "{who} must not hear a press"
        );
    }

    let uri = format!(
        "/channels/{}/messages/{}/interactions",
        w.channel,
        sent["id"].as_str().unwrap()
    );
    let (status, _) = call(
        &w,
        "POST",
        &uri,
        &w.alice.1,
        Some(json!({ "id": id, "custom_id": "hit" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        frame_of_kind(&mut bot, "interaction.created")
            .await
            .is_none(),
        "a retry is not a second press"
    );
    let (status, _) = call(
        &w,
        "POST",
        &uri,
        &w.bob.1,
        Some(json!({ "id": id, "custom_id": "hit" })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "an id belongs to one clicker");
}

#[tokio::test]
async fn only_a_live_enabled_button_on_a_bots_message_can_be_pressed() {
    let w = world().await;
    let sent = posted(&w).await;
    let (status, _, _) = press(&w, &w.alice.1, &sent, "nope").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _, _) = press(&w, &w.alice.1, &sent, "rules").await;
    assert_eq!(
        status,
        StatusCode::NOT_FOUND,
        "a link button never reaches a bot"
    );
    let (status, _, _) = press(&w, &w.bot.1, &sent, "hit").await;
    assert_eq!(status, StatusCode::FORBIDDEN, "a bot cannot press");

    let plain = call(
        &w,
        "POST",
        &format!("/channels/{}/messages", w.channel),
        &w.bob.1,
        Some(json!({ "id": Uuid::now_v7().to_string(), "content": "hi" })),
    )
    .await
    .1;
    let (status, _, _) = press(&w, &w.alice.1, &plain, "hit").await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let uri = format!(
        "/channels/{}/messages/{}",
        w.channel,
        sent["id"].as_str().unwrap()
    );
    call(&w, "DELETE", &uri, &w.bot.1, None).await;
    let (status, _, _) = press(&w, &w.alice.1, &sent, "hit").await;
    assert_eq!(
        status,
        StatusCode::NOT_FOUND,
        "a deleted message has no buttons"
    );
}

#[tokio::test]
async fn a_held_down_button_is_rate_limited_per_clicker() {
    let w = world().await;
    let sent = posted(&w).await;
    let mut last = StatusCode::OK;
    for _ in 0..12 {
        last = press(&w, &w.alice.1, &sent, "hit").await.0;
    }
    assert_eq!(last, StatusCode::TOO_MANY_REQUESTS);
    let (status, _, _) = press(&w, &w.bob.1, &sent, "hit").await;
    assert_eq!(
        status,
        StatusCode::OK,
        "another clicker has their own budget"
    );
}

#[tokio::test]
async fn a_private_reply_to_a_press_reaches_only_the_clicker_and_is_budgeted() {
    let w = world().await;
    let sent = posted(&w).await;
    let addr = serve(w.state.clone()).await;
    let mut alice = connect(&w, addr, &w.alice.1).await;
    let mut bob = connect(&w, addr, &w.bob.1).await;
    let (_, _, id) = press(&w, &w.alice.1, &sent, "hit").await;

    assert_eq!(
        whisper(&w, &w.bot.1, &id, "you drew a king").await,
        StatusCode::OK
    );
    assert!(
        frame_of_kind(&mut alice, "interaction.answered")
            .await
            .is_some()
    );
    let heard = frame_of_kind(&mut alice, "message.ephemeral")
        .await
        .expect("the clicker hears it");
    assert_eq!(heard["message"]["content"], "you drew a king");
    assert!(frame_of_kind(&mut bob, "message.ephemeral").await.is_none());
    assert!(
        frame_of_kind(&mut bob, "interaction.answered")
            .await
            .is_none()
    );

    assert_eq!(whisper(&w, &w.bot.1, &id, "two").await, StatusCode::OK);
    assert_eq!(whisper(&w, &w.bot.1, &id, "three").await, StatusCode::OK);
    assert_eq!(
        whisper(&w, &w.bot.1, &id, "four").await,
        StatusCode::FORBIDDEN,
        "three replies per press"
    );
}

#[tokio::test]
async fn another_bot_cannot_answer_a_press_it_was_not_sent() {
    let w = world().await;
    let sent = posted(&w).await;
    let (_, _, id) = press(&w, &w.alice.1, &sent, "hit").await;
    assert_eq!(
        whisper(&w, &w.other_bot.1, &id, "gotcha").await,
        StatusCode::FORBIDDEN
    );
    let (status, _) = call(
        &w,
        "POST",
        &format!("/channels/{}/interactions/{id}/ack", w.channel),
        &w.other_bot.1,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn an_ack_tells_the_clicker_once_and_nobody_else() {
    let w = world().await;
    let sent = posted(&w).await;
    let addr = serve(w.state.clone()).await;
    let mut alice = connect(&w, addr, &w.alice.1).await;
    let mut bob = connect(&w, addr, &w.bob.1).await;
    let (_, _, id) = press(&w, &w.alice.1, &sent, "hit").await;
    let uri = format!("/channels/{}/interactions/{id}/ack", w.channel);
    for _ in 0..2 {
        let (status, _) = call(&w, "POST", &uri, &w.bot.1, None).await;
        assert_eq!(status, StatusCode::NO_CONTENT);
    }
    let frame = frame_of_kind(&mut alice, "interaction.answered")
        .await
        .unwrap();
    assert_eq!(frame["interaction_id"], id);
    assert!(
        frame_of_kind(&mut alice, "interaction.answered")
            .await
            .is_none(),
        "told once"
    );
    assert!(
        frame_of_kind(&mut bob, "interaction.answered")
            .await
            .is_none()
    );
}

#[tokio::test]
async fn a_bot_replaces_its_buttons_and_every_viewer_is_told() {
    let w = world().await;
    let sent = posted(&w).await;
    let addr = serve(w.state.clone()).await;
    let mut bob = connect(&w, addr, &w.bob.1).await;
    let mut alice = connect(&w, addr, &w.alice.1).await;
    let (_, _, id) = press(&w, &w.alice.1, &sent, "stand").await;

    let uri = format!(
        "/channels/{}/messages/{}/components",
        w.channel,
        sent["id"].as_str().unwrap()
    );
    let disabled = json!([{ "buttons": [{ "label": "Hit", "style": "primary", "custom_id": "hit", "disabled": true }] }]);
    let (status, _) = call(
        &w,
        "PUT",
        &uri,
        &w.bot.1,
        Some(json!({ "components": disabled, "interaction_id": id })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let frame = frame_of_kind(&mut bob, "message.components").await.unwrap();
    assert_eq!(frame["components"][0]["buttons"][0]["disabled"], true);
    assert!(
        frame_of_kind(&mut alice, "interaction.answered")
            .await
            .is_some(),
        "an edit that names the press answers it"
    );

    let (status, _, _) = press(&w, &w.alice.1, &sent, "hit").await;
    assert_eq!(
        status,
        StatusCode::NOT_FOUND,
        "a disabled button cannot be pressed"
    );
    let (status, _) = call(
        &w,
        "PUT",
        &uri,
        &w.other_bot.1,
        Some(json!({ "components": [] })),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::FORBIDDEN,
        "only the author bot may change them"
    );
    let (status, _) = call(
        &w,
        "PUT",
        &uri,
        &w.alice.1,
        Some(json!({ "components": [] })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, cleared) =
        call(&w, "PUT", &uri, &w.bot.1, Some(json!({ "components": [] }))).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(cleared["components"], json!([]));
    let (_, page) = call(
        &w,
        "GET",
        &format!("/channels/{}/messages", w.channel),
        &w.alice.1,
        None,
    )
    .await;
    assert_eq!(page[0]["components"], json!([]));
}
