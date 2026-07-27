// SPDX-License-Identifier: AGPL-3.0-only
//! HTTP integration tests for attachments: the fetch permission gate (the
//! most important one here, since an unguessable hex id is not access
//! control on its own), the content-type allowlist (including a lying
//! filename or Content-Type header), the security headers a fetch carries,
//! filename sanitization, the size ceiling, rate limiting, and attachment
//! release on message delete.

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::ids::UserId;
use slimm_server::media::Media;
use slimm_server::permissions::Permissions;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use tower::ServiceExt;
use uuid::Uuid;

/// Small enough that the over-size test does not need to allocate real
/// megabytes to exceed it.
const TEST_MAX_ATTACHMENT_BYTES: u64 = 4096;

async fn new_store() -> Store {
    let path = std::env::temp_dir()
        .join(format!("slimm-attachments-test-{}.db", Uuid::now_v7()))
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

fn media_for_test() -> Media {
    let root = std::env::temp_dir().join(format!("slimm-media-test-{}", Uuid::now_v7()));
    Media::new(root, TEST_MAX_ATTACHMENT_BYTES).expect("create temp media directories")
}

fn app(store: Store) -> Router {
    http::router(AppState {
        store,
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: slimm_server::voice::VoiceService::disabled(),
        media: media_for_test(),
    })
}

fn request_json(method: &str, uri: &str, token: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(uri)
        .header("authorization", format!("Bearer {token}"))
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

fn request_bytes(method: &str, uri: &str, token: &str, body: Vec<u8>) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(uri)
        .header("authorization", format!("Bearer {token}"))
        .body(Body::from(body))
        .unwrap()
}

fn request_plain(method: &str, uri: &str, token: &str) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(uri)
        .header("authorization", format!("Bearer {token}"))
        .body(Body::empty())
        .unwrap()
}

async fn json_body(response: axum::response::Response) -> Value {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

/// A member with a session, built straight through the store (see
/// `message_endpoints.rs` for why: joining a claimed deployment is an
/// invite-gated policy pinned by its own tests, and these do not need it).
async fn register(store: &Store, username: &str) -> (String, UserId) {
    let account = store
        .create_account(username, username, "not-a-real-hash")
        .await
        .unwrap();
    store.bootstrap_deployment(account.id).await.unwrap();
    let tokens = store.open_session(account.id, "cli").await.unwrap();
    (tokens.access_token, account.id)
}

/// A minimal, validly-sniffable PNG: only the 8-byte magic number matters to
/// the allowlist, so the rest is arbitrary padding to reach a given size.
fn png(padding: usize) -> Vec<u8> {
    let mut bytes = vec![0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    bytes.extend(std::iter::repeat_n(0u8, padding));
    bytes
}

async fn upload(app: &Router, token: &str, filename: &str, bytes: Vec<u8>) -> Value {
    let response = app
        .clone()
        .oneshot(request_bytes(
            "POST",
            &format!("/attachments?filename={filename}"),
            token,
            bytes,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::CREATED);
    json_body(response).await
}

/// The single most important test in this file: a channel permission, not an
/// unguessable id, is what gates a fetch. Bob can authenticate but holds no
/// role granting VIEW_CHANNEL in the channel alice attached the file to, and
/// must be refused even though he has the exact, correct attachment id.
#[tokio::test]
async fn fetching_requires_view_channel_permission() {
    let store = new_store().await;
    // @everyone gets nothing; alice is separately granted what she needs so
    // bob (plain @everyone) genuinely cannot view the channel.
    store
        .create_role("everyone", Permissions::NONE, true)
        .await
        .unwrap();
    let can_post = store
        .create_role(
            "poster",
            Permissions::VIEW_CHANNEL
                .union(Permissions::SEND_MESSAGES)
                .union(Permissions::ATTACH_FILES),
            false,
        )
        .await
        .unwrap();
    let channel = store.create_channel("general", "text").await.unwrap();
    let app = app(store.clone());
    let (alice_token, alice_id) = register(&store, "alice").await;
    store.assign_role(alice_id, can_post).await.unwrap();
    let (bob_token, _bob_id) = register(&store, "bob").await;

    let uploaded = upload(&app, &alice_token, "secret.png", png(16)).await;
    let attachment_id = uploaded["id"].as_str().unwrap().to_owned();

    let sent = app
        .clone()
        .oneshot(request_json(
            "POST",
            &format!("/channels/{}/messages", channel.id),
            &alice_token,
            json!({
                "id": Uuid::now_v7().to_string(),
                "content": "look at this",
                "attachment_ids": [attachment_id],
            }),
        ))
        .await
        .unwrap();
    assert_eq!(sent.status(), StatusCode::OK);
    let sent = json_body(sent).await;
    assert_eq!(
        sent["attachments"].as_array().unwrap().len(),
        1,
        "a fresh send must echo its own attachment immediately"
    );

    let fetch_uri = format!("/attachments/{attachment_id}");

    // Bob cannot see the channel, so he cannot fetch the attachment either,
    // despite knowing its exact, correct id.
    let forbidden = app
        .clone()
        .oneshot(request_plain("GET", &fetch_uri, &bob_token))
        .await
        .unwrap();
    assert_eq!(
        forbidden.status(),
        StatusCode::FORBIDDEN,
        "an unguessable id is not access control"
    );

    // Control: alice, who can view the channel, can fetch it.
    let allowed = app
        .clone()
        .oneshot(request_plain("GET", &fetch_uri, &alice_token))
        .await
        .unwrap();
    assert_eq!(allowed.status(), StatusCode::OK);
}

#[tokio::test]
async fn an_oversized_upload_is_refused() {
    let store = new_store().await;
    store
        .create_role("everyone", Permissions::VIEW_CHANNEL, true)
        .await
        .unwrap();
    let app = app(store.clone());
    let (token, _id) = register(&store, "alice").await;

    let too_big = png(TEST_MAX_ATTACHMENT_BYTES as usize + 1);
    let response = app
        .clone()
        .oneshot(request_bytes(
            "POST",
            "/attachments?filename=big.png",
            &token,
            too_big,
        ))
        .await
        .unwrap();
    assert!(
        !response.status().is_success(),
        "a body over the configured ceiling must be refused, got {}",
        response.status()
    );
}

/// The filename and an explicit Content-Type header both claim an image, but
/// the bytes are HTML. Neither signal is trusted - only the bytes are sniffed
/// - so this must be refused exactly like an honestly labeled HTML upload
/// would be.
#[tokio::test]
async fn a_disallowed_content_type_is_refused_even_when_the_filename_lies() {
    let store = new_store().await;
    store
        .create_role("everyone", Permissions::VIEW_CHANNEL, true)
        .await
        .unwrap();
    let app = app(store.clone());
    let (token, _id) = register(&store, "alice").await;

    let evil = b"<html><body><script>alert(1)</script></body></html>".to_vec();
    let request = Request::builder()
        .method("POST")
        .uri("/attachments?filename=totally-a-photo.png")
        .header("authorization", format!("Bearer {token}"))
        .header("content-type", "image/png")
        .body(Body::from(evil))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn the_served_response_carries_nosniff_and_a_safe_disposition() {
    let store = new_store().await;
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
    let app = app(store.clone());
    let (token, _id) = register(&store, "alice").await;

    let uploaded = upload(&app, &token, "photo.png", png(8)).await;
    let attachment_id = uploaded["id"].as_str().unwrap().to_owned();
    app.clone()
        .oneshot(request_json(
            "POST",
            &format!("/channels/{}/messages", channel.id),
            &token,
            json!({
                "id": Uuid::now_v7().to_string(),
                "content": "a photo",
                "attachment_ids": [attachment_id.clone()],
            }),
        ))
        .await
        .unwrap();

    let response = app
        .clone()
        .oneshot(request_plain(
            "GET",
            &format!("/attachments/{attachment_id}"),
            &token,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let headers = response.headers().clone();
    assert_eq!(headers.get("x-content-type-options").unwrap(), "nosniff");
    assert_eq!(headers.get("content-type").unwrap(), "image/png");
    let disposition = headers
        .get("content-disposition")
        .unwrap()
        .to_str()
        .unwrap();
    assert!(
        disposition.starts_with("inline"),
        "a known-safe image type may render inline: {disposition}"
    );
    assert!(disposition.contains("photo.png"));
}

#[tokio::test]
async fn a_non_image_attachment_is_served_as_a_forced_download() {
    let store = new_store().await;
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
    let app = app(store.clone());
    let (token, _id) = register(&store, "alice").await;

    let pdf = b"%PDF-1.7 rest of a not-really-a-pdf".to_vec();
    let uploaded = upload(&app, &token, "doc.pdf", pdf).await;
    let attachment_id = uploaded["id"].as_str().unwrap().to_owned();
    assert_eq!(uploaded["content_type"], "application/pdf");
    app.clone()
        .oneshot(request_json(
            "POST",
            &format!("/channels/{}/messages", channel.id),
            &token,
            json!({
                "id": Uuid::now_v7().to_string(),
                "content": "a document",
                "attachment_ids": [attachment_id.clone()],
            }),
        ))
        .await
        .unwrap();

    let response = app
        .clone()
        .oneshot(request_plain(
            "GET",
            &format!("/attachments/{attachment_id}"),
            &token,
        ))
        .await
        .unwrap();
    let disposition = response
        .headers()
        .get("content-disposition")
        .unwrap()
        .to_str()
        .unwrap()
        .to_owned();
    assert!(
        disposition.starts_with("attachment"),
        "everything but an allowlisted image type must force a download: {disposition}"
    );
}

/// Storage never uses the filename as a path component at all (files are keyed
/// by content hash), so the traversal has nowhere to escape to even before
/// sanitizing; this asserts the whole round trip still behaves, not just the
/// sanitizer in isolation.
#[tokio::test]
async fn a_hostile_filename_cannot_escape_into_the_header_or_the_storage_path() {
    let store = new_store().await;
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
    let app = app(store.clone());
    let (token, _id) = register(&store, "alice").await;

    // A newline (header injection), a quote (breaking out of the quoted
    // Content-Disposition value) and a path traversal sequence, in one name.
    let hostile = "evil\r\nX-Injected: yes\"../../../etc/passwd.png";
    let encoded = urlencoding_minimal(hostile);
    let bytes = png(4);
    let uploaded = upload(&app, &token, &encoded, bytes.clone()).await;
    let filename = uploaded["filename"].as_str().unwrap();
    assert!(!filename.contains('\r'));
    assert!(!filename.contains('\n'));
    assert!(!filename.contains('"'));
    assert!(!filename.contains('/'));
    assert!(!filename.contains('\\'));

    let attachment_id = uploaded["id"].as_str().unwrap().to_owned();
    let sent = app
        .clone()
        .oneshot(request_json(
            "POST",
            &format!("/channels/{}/messages", channel.id),
            &token,
            json!({
                "id": Uuid::now_v7().to_string(),
                "content": "x",
                "attachment_ids": [attachment_id.clone()],
            }),
        ))
        .await
        .unwrap();
    assert_eq!(sent.status(), StatusCode::OK);

    let response = app
        .clone()
        .oneshot(request_plain(
            "GET",
            &format!("/attachments/{attachment_id}"),
            &token,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    // The raw header value, not just the JSON field: a `HeaderValue` cannot
    // even hold a literal CR or LF, so it can never have held the raw name.
    let disposition = response
        .headers()
        .get("content-disposition")
        .unwrap()
        .to_str()
        .unwrap();
    assert!(!disposition.contains('\r'));
    assert!(!disposition.contains('\n'));
    // Exactly two quotes: the pair the filename is wrapped in, and none from
    // the hostile input itself.
    assert_eq!(disposition.matches('"').count(), 2);

    // Storage never used the filename as a path, so the bytes read back are
    // exactly what was uploaded regardless of what the name claimed.
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    assert_eq!(body.as_ref(), bytes.as_slice());
}

/// Percent-encodes just enough (CR, LF, the quote, and the space a real
/// client would also need to escape) to make the hostile filename a legal
/// query-string value; a real client's URL encoder would do the same.
fn urlencoding_minimal(raw: &str) -> String {
    raw.chars()
        .map(|c| match c {
            '\r' => "%0D".to_owned(),
            '\n' => "%0A".to_owned(),
            '"' => "%22".to_owned(),
            ' ' => "%20".to_owned(),
            other => other.to_string(),
        })
        .collect()
}

#[tokio::test]
async fn deleting_a_message_releases_its_attachment() {
    let store = new_store().await;
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
    let app = app(store.clone());
    let (token, _id) = register(&store, "alice").await;

    let uploaded = upload(&app, &token, "gone-soon.png", png(4)).await;
    let attachment_id = uploaded["id"].as_str().unwrap().to_owned();
    let message_id = Uuid::now_v7().to_string();
    let sent = app
        .clone()
        .oneshot(request_json(
            "POST",
            &format!("/channels/{}/messages", channel.id),
            &token,
            json!({
                "id": message_id,
                "content": "temporary",
                "attachment_ids": [attachment_id.clone()],
            }),
        ))
        .await
        .unwrap();
    assert_eq!(sent.status(), StatusCode::OK);

    let fetch_uri = format!("/attachments/{attachment_id}");
    let before = app
        .clone()
        .oneshot(request_plain("GET", &fetch_uri, &token))
        .await
        .unwrap();
    assert_eq!(before.status(), StatusCode::OK, "sanity: it exists first");

    let deleted = app
        .clone()
        .oneshot(request_plain(
            "DELETE",
            &format!("/channels/{}/messages/{message_id}", channel.id),
            &token,
        ))
        .await
        .unwrap();
    assert_eq!(deleted.status(), StatusCode::NO_CONTENT);

    let after = app
        .clone()
        .oneshot(request_plain("GET", &fetch_uri, &token))
        .await
        .unwrap();
    assert_eq!(
        after.status(),
        StatusCode::NOT_FOUND,
        "a deleted message's attachment must no longer be fetchable"
    );
}

#[tokio::test]
async fn uploads_are_rate_limited() {
    let store = new_store().await;
    store
        .create_role("everyone", Permissions::VIEW_CHANNEL, true)
        .await
        .unwrap();
    let app = app(store.clone());
    let (token, _id) = register(&store, "alice").await;

    let mut statuses = Vec::new();
    for i in 0..20 {
        let response = app
            .clone()
            .oneshot(request_bytes(
                "POST",
                &format!("/attachments?filename=f{i}.png"),
                &token,
                png(i),
            ))
            .await
            .unwrap();
        statuses.push(response.status());
    }

    assert!(
        statuses.contains(&StatusCode::CREATED),
        "the first uploads inside the burst are answered: {statuses:?}"
    );
    assert!(
        statuses.contains(&StatusCode::TOO_MANY_REQUESTS),
        "a sustained upload flood must be refused: {statuses:?}"
    );
}
