// SPDX-License-Identifier: AGPL-3.0-only
//! Generates the cross-repo push-envelope contract fixture.
//!
//! The relay lives in a different repository and language
//! (slim-m-relay/internal/api/push_relay_contract_test.go), so nothing short
//! of actually running both sides catches one drifting out from under the
//! other. This test captures the literal JSON bodies slimm-server's real
//! relay client POSTs to `/v1/send` for two genuine message sends - one to
//! an iOS-registered device, one to an Android-registered device, the whole
//! platform vocabulary [`RegisterRequest`](slimm_server) accepts today -
//! driven through the full stack (store, HTTP handler,
//! [`slimm_server::push`], and a real `reqwest` client), so neither is ever
//! a re-serialization of the wire types against themselves.
//!
//! Four synthetic edge-case entries (a payload at and just over the relay's
//! documented 4096-byte limit, an unknown `kind`, and an unknown `platform`)
//! are appended in the same wire shape. Each is built by cloning one of the
//! two real entries above and overriding only the one or two fields that
//! case is actually about - a payload's length, or a deliberately-invalid
//! `kind` or `platform` - so every field not under test in a synthetic case
//! (`platform` and `kind` for the payload-boundary cases; `kind` for the
//! unknown-platform case; `platform` for the unknown-kind case) is a value
//! the server genuinely produced this run, not a literal retyped from
//! scratch that could quietly stop matching what `envelope.rs`/`relay.rs`
//! actually emit. `kind` can only ever be `"message"` today - `PushKind`
//! only encodes that one variant - so every entry, real and synthetic
//! alike, carries whichever real kind value this run produced; the relay
//! must still reject an outright-unknown `kind` or `platform`, which is
//! exactly the failure mode this contract exists to close off before it
//! ships.
//!
//! Run standalone (`cargo test --all`), this test only asserts the two real
//! entries' own shape: it is not the relay-facing check. Exporting the
//! fixture for `TestPushRelayContract` to consume needs
//! `SLIMM_PUSH_CONTRACT_FIXTURE_OUT` set to a path inside a sibling
//! slim-m-relay checkout; the `push-relay-contract` workflow sets it.
//! Without it, the fixture is written under `CARGO_TARGET_TMPDIR` and
//! nothing else reads it, so this test costs nothing extra in the ordinary
//! `cargo test --all` run.

use std::collections::BTreeSet;
use std::path::PathBuf;
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

/// The push tokens behind the fixture's two genuinely server-produced
/// entries, one per platform this server can register a device for today. A
/// token is otherwise opaque to the relay, so reusing it as each case's name
/// (matched against `contractCases` on the Go side) needs no separate
/// metadata channel.
const REAL_CASE_TOKEN_IOS: &str = "contract-real-message";
const REAL_CASE_TOKEN_ANDROID: &str = "contract-real-message-android";

/// Matches the relay's own `maxPayloadBytes` (internal/api/send.go). Kept
/// as a literal here, not imported from anywhere, deliberately: this test's
/// job is to notice if that literal and this one ever say something
/// different, not to assume they agree.
const RELAY_MAX_PAYLOAD_BYTES: usize = 4096;

async fn new_store() -> Store {
    let path = format!(
        "/tmp/slimm-push-contract-fixture-test-{}.db",
        uuid::Uuid::now_v7()
    );
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

async fn register_user(app: &Router, username: &str) -> String {
    let response = app
        .clone()
        .oneshot(request(
            "POST",
            "/auth/register",
            None,
            Some(json!({
                "username": username,
                "display_name": username,
                "password": "hunter2hunter2",
                "device_name": "phone"
            })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), axum::http::StatusCode::OK);
    let body = json_body(response).await;
    body["access_token"].as_str().unwrap().to_owned()
}

/// Registers a real device keypair for push over HTTP, exactly the request
/// shape a client sends, so what gets sealed downstream is sealed to a key
/// the "device" (this test) actually holds and can unseal. `platform` is
/// "ios" or "android" - [`http::push`](slimm_server)'s `RegisterRequest`
/// accepts nothing else - so the caller picks which of the relay's two
/// platforms this device's real, later-captured entry will exercise.
async fn register_push(app: &Router, token: &str, platform: &str, push_token: &str) -> SecretKey {
    let secret = SecretKey::generate(&mut OsRng.unwrap_err());
    let public = secret.public_key();
    let response = app
        .clone()
        .oneshot(request(
            "PUT",
            "/push",
            Some(token),
            Some(json!({
                "platform": platform,
                "push_token": push_token,
                "push_public_key": BASE64.encode(public.as_bytes()),
            })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), axum::http::StatusCode::NO_CONTENT);
    secret
}

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

/// A real HTTP server on an ephemeral loopback port standing in for the
/// relay, capturing the one `/v1/send` body it receives so the test can
/// inspect exactly what `slimm_server::push` put on the wire. Reports
/// everything delivered: this fixture only needs the outbound request, not
/// the response-handling paths `tests/push_endpoints.rs` already covers.
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

/// Finds the one captured message bound for `token`, by value so the caller
/// can go on to build synthetic entries from it without fighting borrows
/// against the shared `messages` slice.
fn find_entry(messages: &[Value], token: &str) -> Value {
    messages
        .iter()
        .find(|m| m["token"] == token)
        .unwrap_or_else(|| panic!("no captured relay-bound entry for token {token:?}"))
        .clone()
}

/// Asserts a genuinely server-produced entry has exactly the shape the relay
/// contract requires: the real `platform` and `token` requested, `kind`
/// still `"message"` (all `PushKind` encodes today), a `payload` that
/// unseals with the device's own key, and nothing else - a field rename or
/// an extra field fails right here, in server CI, before it ever reaches the
/// relay.
fn assert_real_entry_shape(
    entry: &Value,
    want_platform: &str,
    want_token: &str,
    secret: &SecretKey,
) {
    assert_eq!(entry["platform"], want_platform);
    assert_eq!(entry["token"], want_token);
    assert_eq!(entry["kind"], "message");
    let payload = entry["payload"].as_str().expect("payload is a JSON string");
    let sealed = BASE64.decode(payload).expect("payload is valid base64");
    secret
        .unseal(&sealed)
        .expect("payload unseals with the device's own key");
    let keys: BTreeSet<_> = entry
        .as_object()
        .expect("entry is a JSON object")
        .keys()
        .cloned()
        .collect();
    let expected_keys: BTreeSet<_> = ["kind", "payload", "platform", "token"]
        .into_iter()
        .map(String::from)
        .collect();
    assert_eq!(
        keys, expected_keys,
        "the relay-bound message must carry exactly these four fields, nothing more or less"
    );
}

/// Clones a genuinely server-produced entry and overrides only the named
/// fields, so a synthetic edge case's fields that are not the point of that
/// case (see the doc comment on [`push_relay_contract_fixture`]) stay
/// whatever the server actually emitted this run.
fn with_overrides(base: &Value, overrides: &[(&str, &str)]) -> Value {
    let mut entry = base.clone();
    let obj = entry.as_object_mut().expect("entry is a JSON object");
    for &(key, value) in overrides {
        obj.insert(key.to_owned(), json!(value));
    }
    entry
}

/// Where the fixture is written. The cross-repo `push-relay-contract`
/// workflow points this at a path inside its sibling slim-m-relay checkout;
/// left unset (every ordinary `cargo test`), it lands under the real Cargo
/// target directory, which is already gitignored, so a plain local test run
/// never leaves a stray file in the tree.
fn fixture_out_path() -> PathBuf {
    if let Ok(explicit) = std::env::var("SLIMM_PUSH_CONTRACT_FIXTURE_OUT") {
        return PathBuf::from(explicit);
    }
    PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("push_relay_contract.generated.json")
}

#[tokio::test]
async fn push_relay_contract_fixture() {
    let (store, channel_id) = seeded_store().await;
    let (captured, relay_url) = spawn_capturing_relay().await;
    let push = PushSender::with_debounce_window_ms(
        &Config {
            port: 0,
            database_path: String::new(),
            hash_concurrency: 2,
            push_relay_url: Some(relay_url),
            push_relay_key: Some("test-relay-key".to_owned()),
        },
        50,
    )
    .expect("push sender");

    let app = app(store.clone(), push);
    let alice_token = register_user(&app, "alice").await;
    let bob_token = register_user(&app, "bob").await;
    let carol_token = register_user(&app, "carol").await;
    let bob_secret = register_push(&app, &bob_token, "ios", REAL_CASE_TOKEN_IOS).await;
    let carol_secret = register_push(&app, &carol_token, "android", REAL_CASE_TOKEN_ANDROID).await;

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
    assert_eq!(sent.status(), axum::http::StatusCode::OK);

    let captured_body = wait_for_capture(&captured).await;
    let messages = captured_body["messages"]
        .as_array()
        .expect("the captured body has a messages array");
    assert_eq!(
        messages.len(),
        2,
        "exactly bob's one device and carol's one device were targeted"
    );
    let ios_entry = find_entry(messages, REAL_CASE_TOKEN_IOS);
    let android_entry = find_entry(messages, REAL_CASE_TOKEN_ANDROID);

    // Self-check: this is the part of the contract slim-m alone can verify.
    // A field rename, a dropped field, or a changed kind/platform value
    // fails right here, in server CI, before it ever reaches the relay.
    assert_real_entry_shape(&ios_entry, "ios", REAL_CASE_TOKEN_IOS, &bob_secret);
    assert_real_entry_shape(
        &android_entry,
        "android",
        REAL_CASE_TOKEN_ANDROID,
        &carol_secret,
    );

    // Synthetic edge cases: built by cloning one of the two real entries
    // above and overriding only the field(s) each case is actually about,
    // so every other field - "platform" and "kind" for the payload-boundary
    // cases, "kind" for the unknown-platform case, "platform" for the
    // unknown-kind case - is a value the server genuinely produced this run
    // rather than a literal retyped from scratch that could quietly stop
    // matching what envelope.rs/relay.rs actually emit. The relay must
    // reject each of these outright (see TestPushRelayContract), not accept
    // or silently misroute it.
    let at_limit_payload = "x".repeat(RELAY_MAX_PAYLOAD_BYTES);
    let over_limit_payload = "x".repeat(RELAY_MAX_PAYLOAD_BYTES + 1);
    let synthetic_entries = [
        with_overrides(
            &android_entry,
            &[
                ("token", "contract-payload-at-limit"),
                ("payload", &at_limit_payload),
            ],
        ),
        with_overrides(
            &android_entry,
            &[
                ("token", "contract-payload-over-limit"),
                ("payload", &over_limit_payload),
            ],
        ),
        with_overrides(
            &ios_entry,
            &[
                ("token", "contract-unknown-kind"),
                ("kind", "not-a-real-kind"),
            ],
        ),
        with_overrides(
            &android_entry,
            &[
                ("token", "contract-unknown-platform"),
                ("platform", "windows-phone"),
            ],
        ),
    ];

    let mut all_messages = vec![ios_entry, android_entry];
    all_messages.extend(synthetic_entries);
    let fixture = json!({ "messages": all_messages });

    let out_path = fixture_out_path();
    std::fs::create_dir_all(out_path.parent().expect("fixture path has a parent"))
        .expect("create the fixture's output directory");
    std::fs::write(
        &out_path,
        format!("{}\n", serde_json::to_string_pretty(&fixture).unwrap()),
    )
    .expect("write the push-relay contract fixture");
}
