// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! A forwarded copy follows its original out: deleting or ageing out the
//! original removes every copy, in every channel it was forwarded into.

use super::fixtures::*;
use axum::http::StatusCode;
use serde_json::{Value, json};
use slimm_server::hub::{Event, Hub};
use slimm_server::ids::{ChannelId, MessageId};
use tower::ServiceExt;
use uuid::Uuid;

fn message_id(value: &Value) -> MessageId {
    MessageId(Uuid::parse_str(value["id"].as_str().unwrap()).unwrap())
}

async fn listed_ids(app: &axum::Router, channel: &str, token: &str) -> Vec<Value> {
    let uri = format!("/channels/{channel}/messages");
    let page = json_body(
        app.clone()
            .oneshot(request("GET", &uri, token, None))
            .await
            .unwrap(),
    )
    .await;
    page.as_array()
        .unwrap()
        .iter()
        .map(|m| m["id"].clone())
        .collect()
}

struct Forwarded {
    original: Value,
    same_channel: Value,
    other_channel: Value,
    general: String,
    other: String,
}

/// The original in `general`, one copy of it in `general` and one in `other`.
async fn original_with_two_copies(
    app: &axum::Router,
    store: &slimm_server::store::Store,
    general: ChannelId,
    token: &str,
) -> Forwarded {
    let general = general.to_string();
    let other = store
        .create_channel("other", "text")
        .await
        .unwrap()
        .id
        .to_string();
    let original = send(app, &general, token, "abusive text").await;
    let same_channel =
        json_body(post(app, &general, token, forward_body("", &original)).await).await;
    let other_channel =
        json_body(post(app, &other, token, forward_body("", &original)).await).await;
    Forwarded {
        original,
        same_channel,
        other_channel,
        general,
        other,
    }
}

#[tokio::test]
async fn deleting_the_original_removes_its_copies_everywhere() {
    let (store, _guard) = new_store().await;
    let (channel, token) = open_deployment(&store).await;
    let hub = Hub::new();
    let app = app_with_hub(store.clone(), hub.clone());
    let f = original_with_two_copies(&app, &store, channel, &token).await;

    let mut rx = hub.subscribe();
    let uri = format!(
        "/channels/{}/messages/{}",
        f.general,
        f.original["id"].as_str().unwrap()
    );
    let deleted = app
        .clone()
        .oneshot(request("DELETE", &uri, &token, None))
        .await
        .unwrap();
    assert_eq!(deleted.status(), StatusCode::NO_CONTENT);

    let mut seen: Vec<(ChannelId, MessageId, Option<i64>)> = Vec::new();
    while let Ok(event) = rx.try_recv() {
        if let Event::MessageDeleted {
            channel_id,
            message_id,
            op_seq,
        } = event
        {
            seen.push((channel_id, message_id, op_seq));
        }
    }
    for (copy, channel) in [(&f.same_channel, &f.general), (&f.other_channel, &f.other)] {
        let hit = seen
            .iter()
            .find(|(c, m, _)| c.to_string() == *channel && *m == message_id(copy))
            .expect("a live delete event reaches the channel the copy lives in");
        assert!(
            hit.2.is_some(),
            "the event carries an op seq so sync agrees"
        );
        assert!(
            !listed_ids(&app, channel, &token)
                .await
                .contains(&copy["id"])
        );
    }
}

#[tokio::test]
async fn a_bulk_delete_of_the_original_removes_its_copies() {
    let (store, _guard) = new_store().await;
    let (channel, token) = open_deployment(&store).await;
    let app = app(store.clone());
    let f = original_with_two_copies(&app, &store, channel, &token).await;

    let uri = format!("/channels/{}/messages/bulk-delete", f.general);
    let status = app
        .clone()
        .oneshot(request(
            "POST",
            &uri,
            &token,
            Some(json!({ "message_ids": [f.original["id"]] })),
        ))
        .await
        .unwrap()
        .status();
    assert_eq!(status, StatusCode::NO_CONTENT);
    let left = listed_ids(&app, &f.other, &token).await;
    assert!(!left.contains(&f.other_channel["id"]));
}

#[tokio::test]
async fn ageing_out_the_original_removes_its_copies() {
    let (store, pool, _guard) = new_store_with_pool().await;
    let (channel, token) = open_deployment(&store).await;
    let app = app(store.clone());
    let f = original_with_two_copies(&app, &store, channel, &token).await;

    store.set_message_retention_days(1).await.unwrap();
    sqlx::query("UPDATE messages SET created_at = 1000 WHERE id = ?")
        .bind(message_id(&f.original))
        .execute(&pool)
        .await
        .unwrap();

    let swept = store.sweep_message_retention().await.unwrap();
    let pruned: Vec<MessageId> = swept.pruned.iter().map(|p| p.message_id).collect();
    assert!(pruned.contains(&message_id(&f.original)));
    assert!(pruned.contains(&message_id(&f.same_channel)));
    assert!(pruned.contains(&message_id(&f.other_channel)));
    assert!(swept.pruned.iter().all(|p| p.op_seq.is_some()));
    let left = listed_ids(&app, &f.other, &token).await;
    assert!(!left.contains(&f.other_channel["id"]));
}

/// The access half of the snapshot stays: an edit does not reach a copy.
#[tokio::test]
async fn editing_the_original_leaves_the_copy_as_forwarded() {
    let (store, _guard) = new_store().await;
    let (channel, token) = open_deployment(&store).await;
    let app = app(store.clone());
    let general = channel.to_string();
    let original = send(&app, &general, &token, "as it was").await;
    let forward = json_body(post(&app, &general, &token, forward_body("", &original)).await).await;
    let uri = format!(
        "/channels/{general}/messages/{}",
        original["id"].as_str().unwrap()
    );
    let edited = app
        .clone()
        .oneshot(request(
            "PATCH",
            &uri,
            &token,
            Some(json!({ "content": "rewritten after the fact" })),
        ))
        .await
        .unwrap();
    assert_eq!(edited.status(), StatusCode::OK);
    assert!(
        listed_ids(&app, &general, &token)
            .await
            .contains(&forward["id"])
    );
}
