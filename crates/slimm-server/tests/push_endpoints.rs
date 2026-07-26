// SPDX-License-Identifier: AGPL-3.0-only
//! End-to-end push tests: registration over HTTP, triggering from the message
//! send path against a real (mock) relay, lifecycle gating, debounce, a dead
//! token clearing the registration, a disabled sender being a true no-op, and
//! the envelope actually being content-free.
//!
//! The mock relay is a real HTTP server on an ephemeral loopback port, so the
//! sender under test exercises its real HTTP client end to end; only APNs/FCM
//! themselves are out of reach here, which is exactly what the relay exists to
//! abstract away.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
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
use tower::ServiceExt;

// ---------------------------------------------------------------------------
// Shared fixtures (mirrors the style of tests/message_endpoints.rs)
// ---------------------------------------------------------------------------

async fn new_store() -> Store {
    let path = format!("/tmp/slimm-push-endpoints-test-{}.db", uuid::Uuid::now_v7());
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        push_relay_url: None,
        push_relay_key: None,
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    Store::new(pool)
}

fn app(store: Store, push: PushSender) -> Router {
    http::router(AppState {
        store,
        auth: Auth::new(2).expect("auth service"),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push,
    })
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

async fn json_body(response: axum::response::Response) -> Value {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

/// A member with a session, built straight through the store.
///
/// Deliberately not the `/auth/register` route: joining a claimed deployment
/// is an invite-gated policy decision, and it is pinned by its own tests in
/// `registration_gate.rs`. These tests only need somebody signed in, so going
/// through the store keeps them independent of that policy.
async fn register_user(store: &Store, username: &str) -> (String, String) {
    let account = store
        .create_account(username, username, "not-a-real-hash")
        .await
        .unwrap();
    // The first account through here claims the deployment, exactly as the
    // first real registration does; later ones find it already set up.
    store.bootstrap_deployment(account.id).await.unwrap();
    let tokens = store.open_session(account.id, "cli").await.unwrap();
    (tokens.access_token, account.id.to_string())
}

/// Generates a device keypair and registers it for push over HTTP. Returns
/// the device's secret key (kept only by the "device", never the server) so
/// the test can unseal what it eventually receives.
async fn register_push(app: &Router, token: &str, push_token: &str) -> SecretKey {
    let secret = SecretKey::generate(&mut OsRng.unwrap_err());
    let public = secret.public_key();
    let response = app
        .clone()
        .oneshot(request(
            "PUT",
            "/push",
            Some(token),
            Some(json!({
                "platform": "ios",
                "push_token": push_token,
                "push_public_key": BASE64.encode(public.as_bytes()),
            })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), axum::http::StatusCode::NO_CONTENT);
    secret
}

/// Polls a synchronous condition until it is true or `timeout` elapses.
async fn wait_until<F>(mut check: F, timeout: Duration) -> bool
where
    F: FnMut() -> bool,
{
    let start = std::time::Instant::now();
    loop {
        if check() {
            return true;
        }
        if start.elapsed() > timeout {
            return false;
        }
        tokio::time::sleep(Duration::from_millis(15)).await;
    }
}

/// [`wait_until`] for an async condition (a store query, for example).
async fn wait_until_async<F, Fut>(mut check: F, timeout: Duration) -> bool
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = bool>,
{
    let start = std::time::Instant::now();
    loop {
        if check().await {
            return true;
        }
        if start.elapsed() > timeout {
            return false;
        }
        tokio::time::sleep(Duration::from_millis(15)).await;
    }
}

// ---------------------------------------------------------------------------
// Mock relay: a real HTTP server implementing just `POST /v1/send`.
// ---------------------------------------------------------------------------

#[derive(Default)]
struct RelayState {
    calls: Vec<Value>,
    auth_headers: Vec<Option<String>>,
    status_overrides: HashMap<String, String>,
    /// Every POST increments this, whether or not it goes on to succeed, so a
    /// test can tell "the relay was reached" apart from "the relay delivered".
    attempts: usize,
    /// How many of the next calls should fail outright at the transport
    /// level (a 500), simulating a relay that is briefly unreachable.
    fail_next_calls: usize,
}

#[derive(Clone)]
struct MockRelay {
    state: Arc<Mutex<RelayState>>,
}

impl MockRelay {
    fn call_count(&self) -> usize {
        self.state.lock().unwrap().calls.len()
    }

    /// Every attempted POST, including ones that failed. Never smaller than
    /// [`Self::call_count`].
    fn attempt_count(&self) -> usize {
        self.state.lock().unwrap().attempts
    }

    /// Every message across every successful call, flattened, for asserting
    /// on payloads.
    fn all_messages(&self) -> Vec<Value> {
        self.state
            .lock()
            .unwrap()
            .calls
            .iter()
            .flat_map(|call| call["messages"].as_array().cloned().unwrap_or_default())
            .collect()
    }

    fn set_status(&self, token: &str, status: &str) {
        self.state
            .lock()
            .unwrap()
            .status_overrides
            .insert(token.to_owned(), status.to_owned());
    }

    /// The next `count` calls to `/v1/send` fail at the transport level
    /// instead of returning a result, so the caller sees a relay error rather
    /// than a per-token status.
    fn fail_next_calls(&self, count: usize) {
        self.state.lock().unwrap().fail_next_calls += count;
    }

    fn saw_bearer(&self, key: &str) -> bool {
        let expected = format!("Bearer {key}");
        self.state
            .lock()
            .unwrap()
            .auth_headers
            .iter()
            .all(|h| h.as_deref() == Some(expected.as_str()))
    }
}

async fn handle_send(
    State(mock): State<MockRelay>,
    headers: axum::http::HeaderMap,
    Json(body): Json<Value>,
) -> Result<Json<Value>, axum::http::StatusCode> {
    let auth_header = headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .map(str::to_owned);

    let mut state = mock.state.lock().unwrap();
    state.attempts += 1;
    if state.fail_next_calls > 0 {
        state.fail_next_calls -= 1;
        return Err(axum::http::StatusCode::INTERNAL_SERVER_ERROR);
    }

    let messages = body["messages"].as_array().cloned().unwrap_or_default();
    let results: Vec<Value> = messages
        .iter()
        .map(|m| {
            let token = m["token"].as_str().unwrap_or_default().to_owned();
            let status = state
                .status_overrides
                .get(&token)
                .cloned()
                .unwrap_or_else(|| "delivered".to_owned());
            json!({ "token": token, "status": status })
        })
        .collect();
    state.calls.push(body);
    state.auth_headers.push(auth_header);
    Ok(Json(json!({ "results": results })))
}

/// Spawns the mock relay on an ephemeral loopback port and returns a handle
/// plus its base URL (what `SLIMM_PUSH_RELAY_URL` would be set to).
async fn spawn_mock_relay() -> (MockRelay, String) {
    let mock = MockRelay {
        state: Arc::new(Mutex::new(RelayState::default())),
    };
    let router = Router::new()
        .route("/v1/send", post(handle_send))
        .with_state(mock.clone());
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    (mock, format!("http://{addr}"))
}

fn push_config(relay_url: &str) -> Config {
    Config {
        port: 0,
        database_path: String::new(),
        hash_concurrency: 2,
        push_relay_url: Some(relay_url.to_owned()),
        push_relay_key: Some("test-relay-key".to_owned()),
    }
}

/// Seeds `@everyone` with view+send so every registered user can see and post
/// to the general channel, matching the message-endpoint tests' setup.
async fn seeded_store() -> (Store, slimm_server::ids::ChannelId) {
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
    (store, channel.id)
}

const SHORT_DEBOUNCE_MS: i64 = 150;
const WAIT_TIMEOUT: Duration = Duration::from_secs(5);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn a_disabled_sender_never_reaches_a_relay() {
    let (store, channel_id) = seeded_store().await;
    // A mock relay is running, but the sender under test is disabled and was
    // never told its address: if `PushSender::disabled()` were not a genuine
    // no-op, this is what would catch a stray call.
    let (mock, _addr) = spawn_mock_relay().await;

    let app = app(store.clone(), PushSender::disabled());
    let (alice_token, _alice_id) = register_user(&store, "alice").await;
    let _bob_secret = {
        let (bob_token, _bob_id) = register_user(&store, "bob").await;
        register_push(&app, &bob_token, "bobs-token").await
    };

    let sent = app
        .clone()
        .oneshot(request(
            "POST",
            &format!("/channels/{channel_id}/messages"),
            Some(&alice_token),
            Some(json!({ "id": uuid::Uuid::now_v7().to_string(), "content": "hello" })),
        ))
        .await
        .unwrap();
    assert_eq!(
        sent.status(),
        axum::http::StatusCode::OK,
        "sending still succeeds with push disabled"
    );

    // Give a wrongly-enabled sender every chance to have fired.
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert_eq!(mock.call_count(), 0, "a disabled sender made no HTTP call");
}

#[tokio::test]
async fn a_recipient_gets_a_push_and_the_envelope_carries_no_message_content() {
    let (store, channel_id) = seeded_store().await;
    let (mock, relay_url) = spawn_mock_relay().await;
    let push = PushSender::with_debounce_window_ms(&push_config(&relay_url), SHORT_DEBOUNCE_MS)
        .expect("push sender");

    let app = app(store.clone(), push);
    let (alice_token, _alice_id) = register_user(&store, "alice").await;
    let (bob_token, _bob_id) = register_user(&store, "bob").await;
    let bob_secret = register_push(&app, &bob_token, "bobs-token").await;

    let secret_content = "the launch codes are 8675309, tell nobody";
    let sent = app
        .clone()
        .oneshot(request(
            "POST",
            &format!("/channels/{channel_id}/messages"),
            Some(&alice_token),
            Some(json!({ "id": uuid::Uuid::now_v7().to_string(), "content": secret_content })),
        ))
        .await
        .unwrap();
    assert_eq!(sent.status(), axum::http::StatusCode::OK);
    let sent = json_body(sent).await;
    let message_id = sent["id"].as_str().unwrap().to_owned();

    assert!(
        wait_until(|| mock.call_count() >= 1, WAIT_TIMEOUT).await,
        "the relay was called"
    );
    assert!(mock.saw_bearer("test-relay-key"), "the relay key was sent");

    let messages = mock.all_messages();
    assert_eq!(messages.len(), 1, "exactly bob's device was targeted");
    let msg = &messages[0];
    assert_eq!(msg["platform"], "ios");
    assert_eq!(msg["token"], "bobs-token");
    assert_eq!(msg["kind"], "message");

    let payload = msg["payload"].as_str().unwrap();
    let sealed = BASE64.decode(payload).unwrap();
    let plaintext = bob_secret.unseal(&sealed).expect("unseal with bob's key");
    let plaintext_str = String::from_utf8(plaintext.clone()).unwrap();

    // The envelope carries only routing metadata...
    let envelope: Value = serde_json::from_slice(&plaintext).unwrap();
    assert_eq!(envelope["domain"], "slim-m.push.v1");
    assert_eq!(envelope["version"], 1);
    assert_eq!(envelope["kind"], "message");
    assert_eq!(envelope["channel_id"], channel_id.to_string());
    assert_eq!(envelope["message_id"], message_id);
    assert_eq!(envelope["seq"], 1);
    // ...and only that: exactly these six keys, nothing extra smuggled in.
    let keys: std::collections::BTreeSet<_> =
        envelope.as_object().unwrap().keys().cloned().collect();
    let expected: std::collections::BTreeSet<_> = [
        "domain",
        "version",
        "kind",
        "channel_id",
        "message_id",
        "seq",
    ]
    .into_iter()
    .map(String::from)
    .collect();
    assert_eq!(keys, expected);

    // ...and definitely never the message text or the author's name.
    assert!(!plaintext_str.contains("launch codes"));
    assert!(!plaintext_str.contains("alice"));
    assert!(!plaintext_str.contains("general"));
}

#[tokio::test]
async fn an_unregistered_result_clears_the_registration() {
    let (store, channel_id) = seeded_store().await;
    let (mock, relay_url) = spawn_mock_relay().await;
    let push = PushSender::with_debounce_window_ms(&push_config(&relay_url), SHORT_DEBOUNCE_MS)
        .expect("push sender");

    let app = app(store.clone(), push);
    let (alice_token, _alice_id) = register_user(&store, "alice").await;
    let (bob_token, bob_id) = register_user(&store, "bob").await;
    register_push(&app, &bob_token, "bobs-dead-token").await;
    mock.set_status("bobs-dead-token", "unregistered");

    let bob_id = slimm_server::ids::UserId(uuid::Uuid::parse_str(&bob_id).unwrap());
    assert_eq!(store.push_targets(&[bob_id]).await.unwrap().len(), 1);

    app.clone()
        .oneshot(request(
            "POST",
            &format!("/channels/{channel_id}/messages"),
            Some(&alice_token),
            Some(json!({ "id": uuid::Uuid::now_v7().to_string(), "content": "hi bob" })),
        ))
        .await
        .unwrap();

    assert!(
        wait_until_async(
            || async { store.push_targets(&[bob_id]).await.unwrap().is_empty() },
            WAIT_TIMEOUT
        )
        .await,
        "the dead registration was cleared"
    );
}

#[tokio::test]
async fn a_foreground_device_is_not_pushed() {
    let (store, channel_id) = seeded_store().await;
    let (mock, relay_url) = spawn_mock_relay().await;
    let push = PushSender::with_debounce_window_ms(&push_config(&relay_url), SHORT_DEBOUNCE_MS)
        .expect("push sender");

    let app = app(store.clone(), push);
    let (alice_token, _alice_id) = register_user(&store, "alice").await;

    let (bob_token, _bob_id) = register_user(&store, "bob").await;
    register_push(&app, &bob_token, "bobs-token").await;
    let reported = app
        .clone()
        .oneshot(request(
            "PUT",
            "/push/lifecycle",
            Some(&bob_token),
            Some(json!({ "state": "foreground" })),
        ))
        .await
        .unwrap();
    assert_eq!(reported.status(), axum::http::StatusCode::NO_CONTENT);

    let (carol_token, _carol_id) = register_user(&store, "carol").await;
    register_push(&app, &carol_token, "carols-token").await;
    // Carol never reports a lifecycle state at all, so she is pushed.

    app.clone()
        .oneshot(request(
            "POST",
            &format!("/channels/{channel_id}/messages"),
            Some(&alice_token),
            Some(json!({ "id": uuid::Uuid::now_v7().to_string(), "content": "hi both" })),
        ))
        .await
        .unwrap();

    assert!(
        wait_until(|| mock.call_count() >= 1, WAIT_TIMEOUT).await,
        "the relay was called for carol"
    );
    // Give a wrongly-included bob every chance to have shown up too.
    tokio::time::sleep(Duration::from_millis(200)).await;

    let messages = mock.all_messages();
    assert_eq!(
        messages.len(),
        1,
        "only the non-foreground device was pushed"
    );
    assert_eq!(messages[0]["token"], "carols-token");
}

#[tokio::test]
async fn a_burst_of_messages_in_one_channel_debounces_to_one_push() {
    let (store, channel_id) = seeded_store().await;
    let (mock, relay_url) = spawn_mock_relay().await;
    let push = PushSender::with_debounce_window_ms(&push_config(&relay_url), SHORT_DEBOUNCE_MS)
        .expect("push sender");

    let app = app(store.clone(), push);
    let (alice_token, _alice_id) = register_user(&store, "alice").await;
    let (bob_token, _bob_id) = register_user(&store, "bob").await;
    register_push(&app, &bob_token, "bobs-token").await;

    let send = |content: &str| {
        request(
            "POST",
            &format!("/channels/{channel_id}/messages"),
            Some(&alice_token),
            Some(json!({ "id": uuid::Uuid::now_v7().to_string(), "content": content })),
        )
    };

    // A burst of five messages, well inside the debounce window.
    for i in 0..5 {
        let response = app.clone().oneshot(send(&format!("m{i}"))).await.unwrap();
        assert_eq!(response.status(), axum::http::StatusCode::OK);
    }

    assert!(
        wait_until(|| mock.call_count() >= 1, WAIT_TIMEOUT).await,
        "the first message's push fired"
    );
    // Settle well past the debounce window, then confirm the burst collapsed.
    tokio::time::sleep(Duration::from_millis((SHORT_DEBOUNCE_MS * 3) as u64)).await;
    assert_eq!(mock.call_count(), 1, "the burst collapsed into one push");

    // A message after the window has fully elapsed opens a new window.
    let response = app.clone().oneshot(send("later")).await.unwrap();
    assert_eq!(response.status(), axum::http::StatusCode::OK);
    assert!(
        wait_until(|| mock.call_count() >= 2, WAIT_TIMEOUT).await,
        "a message past the debounce window fires again"
    );
}

#[tokio::test]
async fn a_relay_failure_does_not_swallow_the_next_messages_wake() {
    // Regression: the debounce used to record its window at decision time,
    // before delivery was even attempted, so a leading trigger that failed at
    // the transport level still spent the window and the next message's push
    // was dropped rather than merely collapsed into it.
    let (store, channel_id) = seeded_store().await;
    let (mock, relay_url) = spawn_mock_relay().await;
    let push = PushSender::with_debounce_window_ms(&push_config(&relay_url), SHORT_DEBOUNCE_MS)
        .expect("push sender");

    let app = app(store.clone(), push);
    let (alice_token, _alice_id) = register_user(&store, "alice").await;
    let (bob_token, _bob_id) = register_user(&store, "bob").await;
    register_push(&app, &bob_token, "bobs-token").await;

    let send = |content: &str| {
        request(
            "POST",
            &format!("/channels/{channel_id}/messages"),
            Some(&alice_token),
            Some(json!({ "id": uuid::Uuid::now_v7().to_string(), "content": content })),
        )
    };

    // The leading message's relay call fails outright.
    mock.fail_next_calls(1);
    let sent = app.clone().oneshot(send("first")).await.unwrap();
    assert_eq!(
        sent.status(),
        axum::http::StatusCode::OK,
        "the send still succeeds even though its push attempt fails"
    );
    assert!(
        wait_until(|| mock.attempt_count() >= 1, WAIT_TIMEOUT).await,
        "the first, failing relay call was attempted"
    );
    assert_eq!(mock.call_count(), 0, "it did not actually deliver anything");

    // A second message, well inside what would have been the debounce
    // window, must still reach the relay.
    let sent = app.clone().oneshot(send("second")).await.unwrap();
    assert_eq!(sent.status(), axum::http::StatusCode::OK);
    assert!(
        wait_until(|| mock.call_count() >= 1, WAIT_TIMEOUT).await,
        "the second message's push must not be eaten by the failed leading trigger"
    );
    let messages = mock.all_messages();
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0]["token"], "bobs-token");
}

#[tokio::test]
async fn one_recipients_open_debounce_window_does_not_suppress_another_recipient() {
    // Regression: the debounce used to be keyed on channel id alone, so one
    // recipient's open window silenced every other recipient's first wake in
    // the same channel too.
    //
    // Both accounts are fully registered for push up front, so nothing here
    // depends on exactly when either background delivery task happens to run
    // its own database reads. Carol's first message is awaited all the way
    // through delivery before bob's state changes and the second message is
    // sent, so which task's debounce check would happen to run first is never
    // in question; the debounce window is generously larger than the one
    // cheap, hash-free lifecycle call in between, so it cannot elapse on its
    // own by coincidence either.
    const ISOLATION_DEBOUNCE_MS: i64 = 3_000;

    let (store, channel_id) = seeded_store().await;
    let (mock, relay_url) = spawn_mock_relay().await;
    let push = PushSender::with_debounce_window_ms(&push_config(&relay_url), ISOLATION_DEBOUNCE_MS)
        .expect("push sender");

    let app = app(store.clone(), push);
    let (alice_token, _alice_id) = register_user(&store, "alice").await;
    let (bob_token, _bob_id) = register_user(&store, "bob").await;
    register_push(&app, &bob_token, "bobs-token").await;
    let (carol_token, _carol_id) = register_user(&store, "carol").await;
    register_push(&app, &carol_token, "carols-token").await;

    let report_bob = |state: &str| {
        request(
            "PUT",
            "/push/lifecycle",
            Some(&bob_token),
            Some(json!({ "state": state })),
        )
    };
    let send = |content: &str| {
        request(
            "POST",
            &format!("/channels/{channel_id}/messages"),
            Some(&alice_token),
            Some(json!({ "id": uuid::Uuid::now_v7().to_string(), "content": content })),
        )
    };

    // Bob is currently foreground, so the first message reaches only carol;
    // her debounce window opens. Waited out fully before anything else
    // happens, so there is no ambiguity about which recipient's trigger ran
    // first.
    let reported = app.clone().oneshot(report_bob("foreground")).await.unwrap();
    assert_eq!(reported.status(), axum::http::StatusCode::NO_CONTENT);
    app.clone().oneshot(send("m1")).await.unwrap();
    assert!(
        wait_until(|| mock.call_count() >= 1, WAIT_TIMEOUT).await,
        "carol's push for the first message fired"
    );
    assert_eq!(mock.all_messages().len(), 1);
    assert_eq!(mock.all_messages()[0]["token"], "carols-token");

    // Bob's phone wakes up, still well inside what would be carol's open
    // window, and alice sends a second message.
    let reported = app.clone().oneshot(report_bob("background")).await.unwrap();
    assert_eq!(reported.status(), axum::http::StatusCode::NO_CONTENT);
    app.clone().oneshot(send("m2")).await.unwrap();

    // Bob's very first wake must not be swallowed by carol's already-open,
    // unrelated window: debouncing collapses a burst for one recipient, it
    // does not silence a different recipient entirely.
    assert!(
        wait_until(
            || mock
                .all_messages()
                .iter()
                .any(|m| m["token"] == "bobs-token"),
            WAIT_TIMEOUT
        )
        .await,
        "bob's notification must not be suppressed by carol's debounce window"
    );
}
