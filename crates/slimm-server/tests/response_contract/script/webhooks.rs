// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Incoming webhook delivery, the one route decision 0030 ships in this
//! stage. Minted directly through the store rather than through an admin
//! route, because there is none yet (stage 4): the one thing this route
//! needs, a live `(webhook_id, token)` pair, cannot be reached any other way.

use serde_json::json;
use slimm_server::ids::ChannelId;
use uuid::Uuid;

use crate::world::{Contract, Payload};

/// Drives both documented success shapes: a plain delivery (204, no body)
/// and a `?wait=true` one (200, the minimal acknowledgement DTO), plus a
/// Discord-shaped `embeds` block that must never turn into a 400.
pub(crate) async fn webhook_calls(c: &mut Contract, channel: &str) {
    let channel_id = ChannelId(Uuid::parse_str(channel).expect("a valid channel id"));
    let minted = c
        .store()
        .create_webhook(channel_id, "contract-test-webhook")
        .await
        .expect("minting a webhook directly through the store");
    let path = format!("/webhooks/{}/{}", minted.webhook.id, minted.token);

    c.call(
        "deliverWebhook",
        "POST",
        &path,
        None,
        Payload::Json(json!({
            "content": "an alert fired",
            "embeds": [{"title": "discarded in this stage"}],
        })),
    )
    .await;

    c.call(
        "deliverWebhook",
        "POST",
        &format!("{path}?wait=true"),
        None,
        Payload::Json(json!({ "content": "another alert", "username": "monitor" })),
    )
    .await;
}
