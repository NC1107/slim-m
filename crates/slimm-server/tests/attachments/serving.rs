// SPDX-License-Identifier: AGPL-3.0-only
//! What `GET /attachments/{id}` answers: who is allowed to fetch at all, and
//! what headers and bytes come back when they are.

use axum::http::StatusCode;
use serde_json::json;
use slimm_server::permissions::Permissions;
use tower::ServiceExt;
use uuid::Uuid;

use crate::fixtures::*;

/// The single most important test here: a channel permission, not an
/// unguessable id, is what gates a fetch. Bob can authenticate but holds no
/// role granting VIEW_CHANNEL in the channel alice attached the file to, and
/// must be refused even though he has the exact, correct attachment id.
#[tokio::test]
async fn fetching_requires_view_channel_permission() {
    let (store, _guard) = new_store().await;
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
async fn the_served_response_carries_nosniff_and_a_safe_disposition() {
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
