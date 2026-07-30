// SPDX-License-Identifier: AGPL-3.0-only
//! The half of the pass that builds and reads content: channels, roles and
//! overwrites, then a message carrying every optional part a `Message` has -
//! an attachment, a poll, a reaction and a pin - so the calls that return
//! whole messages return a fully populated one rather than a bare text row.

use serde_json::json;
use slimm_server::permissions::Permissions;
use uuid::Uuid;

use super::{PNG, THUMBS_UP, text};
use crate::world::{Contract, Payload};

/// Builds the channel the message calls run in, plus the role, overwrite and
/// direct-message state, and returns that channel's id.
pub(super) async fn channel_calls(c: &mut Contract, root: &str, bob_id: &str) -> String {
    c.get("listChannels", "/channels", root).await;
    let channel = c
        .json(
            "createChannel",
            "POST",
            "/channels",
            root,
            json!({ "name": "contract", "kind": "text" }),
        )
        .await;
    let channel = text(&channel, "id");
    c.json(
        "updateChannel",
        "PATCH",
        &format!("/channels/{channel}"),
        root,
        json!({ "name": "contract", "topic": "what the schema promises" }),
    )
    .await;
    let scratch = c
        .json(
            "createChannel",
            "POST",
            "/channels",
            root,
            json!({ "name": "scratch", "kind": "voice" }),
        )
        .await;
    c.bare(
        "deleteChannel",
        "DELETE",
        &format!("/channels/{}", text(&scratch, "id")),
        root,
    )
    .await;

    c.bare("openDirectMessage", "POST", &format!("/dms/{bob_id}"), root)
        .await;
    c.get("listDirectMessages", "/dms", root).await;

    c.get("listRoles", "/roles", root).await;
    let role = c
        .json(
            "createRole",
            "POST",
            "/roles",
            root,
            json!({ "name": "mods", "permissions": Permissions::VIEW_CHANNEL.bits() }),
        )
        .await;
    let role = text(&role, "id");
    c.json(
        "updateRole",
        "PATCH",
        &format!("/roles/{role}"),
        root,
        json!({ "name": "moderators" }),
    )
    .await;
    c.bare(
        "assignRole",
        "PUT",
        &format!("/members/{bob_id}/roles/{role}"),
        root,
    )
    .await;
    c.bare(
        "unassignRole",
        "DELETE",
        &format!("/members/{bob_id}/roles/{role}"),
        root,
    )
    .await;
    c.bare("deleteRole", "DELETE", &format!("/roles/{role}"), root)
        .await;

    c.json(
        "placeCanvasObject",
        "POST",
        &format!("/channels/{channel}/canvas/objects"),
        root,
        json!({
            "id": Uuid::now_v7().to_string(),
            "kind": "stroke",
            "x": 100.0, "y": 100.0, "w": 40.0, "h": 20.0,
            "props": { "points": [0.0, 0.0, 40.0, 20.0], "width": 3.0, "color": "annotation" },
        }),
    )
    .await;
    // Placed first, so the read below covers a non-empty page rather than only
    // the envelope a client decodes before anybody has drawn.
    c.get(
        "listCanvasViewport",
        &format!("/channels/{channel}/canvas/objects?min_x=0&min_y=0&max_x=1920&max_y=1080"),
        root,
    )
    .await;

    let overwrite = format!("/channels/{channel}/overwrites/member/{bob_id}");
    c.json(
        "setChannelOverwrite",
        "PUT",
        &overwrite,
        root,
        json!({ "allow": Permissions::VIEW_CHANNEL.bits(), "deny": 0 }),
    )
    .await;
    c.bare("deleteChannelOverwrite", "DELETE", &overwrite, root)
        .await;

    channel
}

/// Sends everything a `Message` can carry - an attachment, a poll, a reaction
/// and a pin - before the two calls that return whole messages read it back.
/// Returns the id of the message the reports below are filed against.
pub(super) async fn message_calls(c: &mut Contract, root: &str, channel: &str) -> String {
    let attachment = c
        .call(
            "uploadAttachment",
            "POST",
            "/attachments?filename=pixel.png",
            Some(root),
            Payload::Bytes(PNG.to_vec()),
        )
        .await;
    let attachment = text(&attachment, "id");
    let messages = format!("/channels/{channel}/messages");
    let sent = c
        .json(
            "sendMessage",
            "POST",
            &messages,
            root,
            json!({
                "id": Uuid::now_v7().to_string(),
                "content": "the first message",
                "attachment_ids": [attachment],
            }),
        )
        .await;
    let message = text(&sent, "id");
    let seq = sent["seq"].as_i64().unwrap_or(0);
    // Only fetchable once a live message references it, so not before now.
    c.get("getAttachment", &format!("/attachments/{attachment}"), root)
        .await;

    c.json(
        "editMessage",
        "PATCH",
        &format!("{messages}/{message}"),
        root,
        json!({ "content": "the first message, edited" }),
    )
    .await;
    let poll = c
        .json(
            "sendPollMessage",
            "POST",
            &format!("{messages}/polls"),
            root,
            json!({
                "id": Uuid::now_v7().to_string(),
                "content": "pick one",
                "question": "does the schema still describe this?",
                "options": ["yes", "no"],
            }),
        )
        .await;
    c.json(
        "votePoll",
        "PUT",
        &format!("/messages/{}/polls/vote", text(&poll, "id")),
        root,
        json!({ "option": 0 }),
    )
    .await;
    c.bare(
        "addReaction",
        "PUT",
        &format!("/messages/{message}/reactions/{THUMBS_UP}"),
        root,
    )
    .await;

    c.bare(
        "pinMessage",
        "PUT",
        &format!("{messages}/{message}/pin"),
        root,
    )
    .await;
    c.get(
        "listPinnedMessages",
        &format!("/channels/{channel}/pins"),
        root,
    )
    .await;
    c.get(
        "getPinnedMessageCount",
        &format!("/channels/{channel}/pins/count"),
        root,
    )
    .await;

    c.get("listMessages", &format!("{messages}?limit=50"), root)
        .await;
    c.get(
        "searchMessages",
        &format!("{messages}/search?q=message&limit=10"),
        root,
    )
    .await;
    c.get("getReadState", &format!("/channels/{channel}/read"), root)
        .await;
    c.json(
        "markRead",
        "PUT",
        &format!("/channels/{channel}/read"),
        root,
        json!({ "seq": seq }),
    )
    .await;

    c.bare(
        "unpinMessage",
        "DELETE",
        &format!("{messages}/{message}/pin"),
        root,
    )
    .await;
    c.bare(
        "removeReaction",
        "DELETE",
        &format!("/messages/{message}/reactions/{THUMBS_UP}"),
        root,
    )
    .await;

    let doomed = c
        .json(
            "sendMessage",
            "POST",
            &messages,
            root,
            json!({ "id": Uuid::now_v7().to_string(), "content": "delete me" }),
        )
        .await;
    c.bare(
        "deleteMessage",
        "DELETE",
        &format!("{messages}/{}", text(&doomed, "id")),
        root,
    )
    .await;

    message
}

/// The deployment's own emoji: add one, list it, fetch its bytes, remove it.
///
/// Uses the same PNG as the attachment above on purpose - the bytes are
/// content-addressed and shared, so this also exercises the case where an
/// emoji points at a hash a message already references.
pub(super) async fn emoji_calls(c: &mut Contract, root: &str) {
    let created = c
        .call(
            "uploadCustomEmoji",
            "POST",
            "/emoji?name=party_parrot",
            Some(root),
            Payload::Bytes(PNG.to_vec()),
        )
        .await;
    let id = text(&created, "id");

    c.get("listCustomEmoji", "/emoji", root).await;
    c.call(
        "fetchCustomEmojiImage",
        "GET",
        &format!("/emoji/{id}/image"),
        Some(root),
        Payload::None,
    )
    .await;
    c.call(
        "deleteCustomEmoji",
        "DELETE",
        &format!("/emoji/{id}"),
        Some(root),
        Payload::None,
    )
    .await;
}
