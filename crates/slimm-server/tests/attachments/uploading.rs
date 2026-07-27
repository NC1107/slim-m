// SPDX-License-Identifier: AGPL-3.0-only
//! What `POST /attachments` accepts: the size ceiling, the byte-sniffed
//! content-type allowlist, and the rate limit on a sustained flood.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use slimm_server::permissions::Permissions;
use tower::ServiceExt;

use crate::fixtures::*;

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
