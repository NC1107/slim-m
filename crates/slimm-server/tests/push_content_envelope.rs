// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! What a device that asked for message content in its push actually gets,
//! and - the point of this file - what the relay gets while that happens.
//!
//! The relay is a shared, stateless forwarder: other people's notifications
//! pass through the same process, so "the relay cannot read a notification"
//! is the property that makes sharing one acceptable at all. Content rides
//! *inside* the sealed box, where it is exactly as opaque to the relay as the
//! channel id already was, and these tests assert that against the real
//! serialized `/v1/send` body captured off a real `reqwest` client, not
//! against the wire structs re-serialized against themselves.
//!
//! [`the_relay_never_sees_content_in_any_field_at_any_depth`] is the one to
//! keep working. It searches the whole serialized request body for the
//! message text, the sender's display name and the channel name, rather than
//! naming the fields it expects them to be absent from, so a field added
//! anywhere in the chain - a new debugging aid, a "title" convenience, a
//! future envelope field accidentally hoisted outside the seal - fails this
//! test rather than passing by not being on its list. It is the same
//! technique `message_ops`' `no_op_carries_an_actor_on_any_kind` uses for the
//! same reason.

use std::time::Duration;

use axum::extract::State;
use axum::routing::post;
use axum::{Json, Router};
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use crypto_box::SecretKey;
use crypto_box::aead::rand_core::{OsRng, TryRngCore};
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
use tokio::sync::Mutex;
use tower::ServiceExt;

mod support;

/// Deliberately long and unlike anything else on the wire, so a substring
/// search for them cannot collide by chance with base64 ciphertext, a uuid,
/// or a field name.
const SENTINEL_BODY: &str = "zzqx-secret-message-body-nobody-else-may-read-zzqx";
const SENTINEL_SENDER: &str = "Zzqx Sentinel Sender Displayname";
const SENTINEL_CHANNEL: &str = "zzqx-sentinel-channel-name";

struct World {
    app: Router,
    /// The same store the router holds, so a test can seed extra accounts
    /// after construction. Cheap to clone: it is a pool handle.
    store: Store,
    channel_id: slimm_server::ids::ChannelId,
    author_token: String,
    captured: std::sync::Arc<Mutex<Option<Value>>>,
    _guard: support::TestDbGuard,
}

async fn world() -> World {
    let (path, guard) = support::TestDbGuard::new("slimm-push-content-envelope-test");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    let store = Store::new(pool);
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES),
            true,
        )
        .await
        .unwrap();
    let channel = store
        .create_channel(SENTINEL_CHANNEL, "text")
        .await
        .unwrap();

    let (captured, relay_url) = spawn_capturing_relay().await;
    let push = PushSender::with_debounce_window_ms(
        &Config {
            port: 0,
            database_path: String::new(),
            hash_concurrency: 2,
            push_relay_url: Some(relay_url),
            push_relay_key: Some("test-relay-key".to_owned()),
            ..Config::default()
        },
        50,
    )
    .expect("push sender");

    let app = http::router(AppState {
        store: store.clone(),
        auth: Auth::new(2).expect("auth service"),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push,
        voice: slimm_server::voice::VoiceService::disabled(),
        media: slimm_server::media::Media::for_tests(),
        gifs: slimm_server::http::gifs::GifSearch::disabled(),
    });

    let author_token = account(&store, "author", SENTINEL_SENDER).await;
    World {
        app,
        store,
        channel_id: channel.id,
        author_token,
        captured,
        _guard: guard,
    }
}

/// An account with a session, built through the store: joining a claimed
/// deployment is an invite-gated policy decision pinned by its own tests, and
/// these only need somebody signed in.
async fn account(store: &Store, username: &str, display_name: &str) -> String {
    let account = store
        .create_account(username, display_name, "not-a-real-hash")
        .await
        .unwrap();
    store.bootstrap_deployment(account.id).await.unwrap();
    store
        .open_session(account.id, "phone")
        .await
        .unwrap()
        .access_token
}

fn request(
    method: &str,
    uri: &str,
    token: Option<&str>,
    body: Option<Value>,
) -> axum::http::Request<axum::body::Body> {
    let mut builder = axum::http::Request::builder().method(method).uri(uri);
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    match body {
        Some(value) => builder
            .header("content-type", "application/json")
            .body(axum::body::Body::from(value.to_string()))
            .unwrap(),
        None => builder.body(axum::body::Body::empty()).unwrap(),
    }
}

/// Registers a real device keypair over the real `PUT /push` route, so what is
/// sealed downstream is sealed to a key this "device" holds and can unseal.
async fn register_push(
    app: &Router,
    token: &str,
    push_token: &str,
    include_content: bool,
) -> SecretKey {
    let secret = SecretKey::generate(&mut OsRng.unwrap_err());
    let response = app
        .clone()
        .oneshot(request(
            "PUT",
            "/push",
            Some(token),
            Some(json!({
                "platform": "ios",
                "push_token": push_token,
                "push_public_key": BASE64.encode(secret.public_key().as_bytes()),
                "include_content": include_content,
            })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), axum::http::StatusCode::NO_CONTENT);
    secret
}

async fn spawn_capturing_relay() -> (std::sync::Arc<Mutex<Option<Value>>>, String) {
    let captured = std::sync::Arc::new(Mutex::new(None));
    let router = Router::new()
        .route(
            "/v1/send",
            post(
                |State(captured): State<std::sync::Arc<Mutex<Option<Value>>>>,
                 Json(body): Json<Value>| async move {
                    let messages = body["messages"].as_array().cloned().unwrap_or_default();
                    let results: Vec<Value> = messages
                        .iter()
                        .map(|m| json!({ "token": m["token"], "status": "delivered" }))
                        .collect();
                    *captured.lock().await = Some(body);
                    Json(json!({ "results": results }))
                },
            ),
        )
        .with_state(captured.clone());
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    (captured, format!("http://{addr}"))
}

/// This crate cannot reach `slimm_server::store::now_ms`, which is
/// `pub(crate)`, so the same clock read is duplicated here for one assertion.
fn epoch_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("after the epoch")
        .as_millis() as i64
}

async fn wait_for_capture(captured: &Mutex<Option<Value>>) -> Value {
    let start = std::time::Instant::now();
    loop {
        if let Some(body) = captured.lock().await.clone() {
            return body;
        }
        assert!(
            start.elapsed() < Duration::from_secs(5),
            "the relay was never called"
        );
        tokio::time::sleep(Duration::from_millis(15)).await;
    }
}

async fn send(world: &World, content: &str) {
    let response = world
        .app
        .clone()
        .oneshot(request(
            "POST",
            &format!("/channels/{}/messages", world.channel_id),
            Some(&world.author_token),
            Some(json!({ "id": uuid::Uuid::now_v7().to_string(), "content": content })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), axum::http::StatusCode::OK);
}

fn entry_for<'a>(body: &'a Value, token: &str) -> &'a Value {
    body["messages"]
        .as_array()
        .expect("messages array")
        .iter()
        .find(|m| m["token"] == token)
        .unwrap_or_else(|| panic!("no relay-bound entry for {token:?}"))
}

/// Unseals one entry's payload with the device's own key and returns the
/// envelope as JSON, which is the only way to read it - exactly the position
/// the relay is in, minus the key.
fn unseal(entry: &Value, secret: &SecretKey) -> Value {
    let sealed = BASE64
        .decode(entry["payload"].as_str().expect("payload is a string"))
        .expect("payload is valid base64");
    let plaintext = secret.unseal(&sealed).expect("unseals with the device key");
    serde_json::from_slice(&plaintext).expect("the envelope is JSON")
}

/// The property that makes a shared relay acceptable: nothing it is handed
/// carries the message, the sender, or the channel, in any field, at any
/// depth. See this file's own module docs for why it searches rather than
/// enumerating fields.
#[tokio::test]
async fn the_relay_never_sees_content_in_any_field_at_any_depth() {
    let world = world().await;
    let recipient = account(&world.store, "reader", "Reader").await;
    let _secret = register_push(&world.app, &recipient, "reader-token", true).await;

    send(&world, SENTINEL_BODY).await;
    let body = wait_for_capture(&world.captured).await;

    let serialized = serde_json::to_string(&body).expect("the captured body re-serializes");
    for (what, sentinel) in [
        ("the message body", SENTINEL_BODY),
        ("the sender's display name", SENTINEL_SENDER),
        ("the channel name", SENTINEL_CHANNEL),
    ] {
        assert!(
            !serialized.contains(sentinel),
            "{what} reached the relay in cleartext, somewhere in: {serialized}"
        );
    }
}

/// Content is in the envelope, and only reachable with the device's own key.
#[tokio::test]
async fn an_opted_in_device_can_unseal_the_sender_channel_and_body() {
    let world = world().await;
    let recipient = account(&world.store, "reader", "Reader").await;
    let secret = register_push(&world.app, &recipient, "reader-token", true).await;

    send(&world, SENTINEL_BODY).await;
    let body = wait_for_capture(&world.captured).await;
    let envelope = unseal(entry_for(&body, "reader-token"), &secret);

    assert_eq!(envelope["body"], SENTINEL_BODY);
    assert_eq!(envelope["sender"], SENTINEL_SENDER);
    assert_eq!(envelope["channel"], SENTINEL_CHANNEL);
    // Untouched routing fields, so catching up over /sync works as before.
    assert_eq!(envelope["channel_id"], world.channel_id.to_string());
    assert_eq!(envelope["kind"], "message");
}

/// The whole defense against a hostile relay retaining and replaying a push:
/// `sent_at` is inside the sealed plaintext, not a routing field the relay
/// could see or hold constant, and it names when the server actually sealed
/// this envelope. Unsealing the real relay-bound payload with the device's
/// own key, the way [`unseal`] does, is what proves it is genuinely inside
/// the sealed box rather than only in the plaintext before it was sealed.
#[tokio::test]
async fn sent_at_is_inside_the_sealed_plaintext_and_recent() {
    let world = world().await;
    let recipient = account(&world.store, "reader", "Reader").await;
    let secret = register_push(&world.app, &recipient, "reader-token", true).await;

    let before = epoch_ms();
    send(&world, SENTINEL_BODY).await;
    let body = wait_for_capture(&world.captured).await;
    let after = epoch_ms();

    let envelope = unseal(entry_for(&body, "reader-token"), &secret);
    let sent_at = envelope["sent_at"]
        .as_i64()
        .expect("sent_at is present and a number");
    assert!(
        (before..=after).contains(&sent_at),
        "sent_at {sent_at} must fall within [{before}, {after}]"
    );
}

/// `sent_at` rides even when a device declined content, since a
/// content-free envelope is exactly as replayable as a preview-carrying one.
#[tokio::test]
async fn sent_at_is_present_even_when_a_device_declined_content() {
    let world = world().await;
    let recipient = account(&world.store, "reader", "Reader").await;
    let secret = register_push(&world.app, &recipient, "reader-token", false).await;

    send(&world, SENTINEL_BODY).await;
    let body = wait_for_capture(&world.captured).await;
    let envelope = unseal(entry_for(&body, "reader-token"), &secret);

    assert!(
        envelope["sent_at"].as_i64().is_some(),
        "a content-free envelope must still carry sent_at: {envelope}"
    );
}

/// A device that did not ask gets what it always got: no content field at
/// all, not a null or an empty string it would have to know to ignore.
///
/// This covers the whole-batch gate, not the per-device split: with nobody
/// opted in, `deliver` never resolves a preview in the first place, so no
/// name lookup even runs. Mutating `seal_for_message` to ignore
/// `include_content` leaves this test green for exactly that reason, which is
/// why [`one_devices_choice_never_reaches_another_devices_envelope`] exists
/// alongside it and is the one that actually fails on that mutation.
#[tokio::test]
async fn a_device_that_did_not_ask_gets_no_content_at_all() {
    let world = world().await;
    let recipient = account(&world.store, "reader", "Reader").await;
    let secret = register_push(&world.app, &recipient, "reader-token", false).await;

    send(&world, SENTINEL_BODY).await;
    let body = wait_for_capture(&world.captured).await;
    let envelope = unseal(entry_for(&body, "reader-token"), &secret);

    for field in ["sender", "channel", "body"] {
        assert!(
            envelope.get(field).is_none(),
            "an opted-out device's envelope must not carry {field}: {envelope}"
        );
    }
    assert_eq!(envelope["channel_id"], world.channel_id.to_string());
}

/// Opting in is per device, so one device asking for content must not put it
/// in a different device's envelope - including a different account's. Sealing
/// happens per target, and this is what fails if that ever becomes one shared
/// plaintext sealed to everybody.
#[tokio::test]
async fn one_devices_choice_never_reaches_another_devices_envelope() {
    let world = world().await;
    let store = world.store.clone();
    let opted_in = account(&store, "reader-in", "Reader In").await;
    let opted_out = account(&store, "reader-out", "Reader Out").await;
    let in_secret = register_push(&world.app, &opted_in, "in-token", true).await;
    let out_secret = register_push(&world.app, &opted_out, "out-token", false).await;

    send(&world, SENTINEL_BODY).await;
    let body = wait_for_capture(&world.captured).await;

    let opted_in_envelope = unseal(entry_for(&body, "in-token"), &in_secret);
    assert_eq!(opted_in_envelope["body"], SENTINEL_BODY);

    let opted_out_envelope = unseal(entry_for(&body, "out-token"), &out_secret);
    assert!(
        opted_out_envelope.get("body").is_none(),
        "the opted-out device's envelope carried the message: {opted_out_envelope}"
    );
}

/// A body past the preview cap is elided rather than sent whole, so one long
/// message cannot push the sealed payload past what the relay and APNs accept
/// - which would be a notification silently lost, not a visible error.
#[tokio::test]
async fn a_long_body_is_truncated_rather_than_sent_whole() {
    let world = world().await;
    let recipient = account(&world.store, "reader", "Reader").await;
    let secret = register_push(&world.app, &recipient, "reader-token", true).await;

    let long = "y".repeat(3_000);
    send(&world, &long).await;
    let body = wait_for_capture(&world.captured).await;
    let entry = entry_for(&body, "reader-token");

    // The relay's own maxPayloadBytes, itself APNs' whole-notification limit.
    let payload = entry["payload"].as_str().expect("payload is a string");
    assert!(
        payload.len() < 4_096,
        "the sealed payload must stay inside the relay's own limit, was {}",
        payload.len()
    );

    let envelope = unseal(entry, &secret);
    let preview = envelope["body"].as_str().expect("body is a string");
    assert!(
        preview.chars().count() < long.chars().count(),
        "a 3000-character message must not be sent whole"
    );
    assert!(
        preview.starts_with("yyy"),
        "the preview is the real message"
    );
}
