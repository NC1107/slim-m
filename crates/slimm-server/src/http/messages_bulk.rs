// SPDX-License-Identifier: AGPL-3.0-only
//! `POST /channels/{id}/messages/bulk-delete`: one moderation act over several
//! messages.
//!
//! Split from `messages.rs` rather than grown into it, the same reason
//! `canvas_ops_apply` sits beside `canvas_ops_write`: that file is already past
//! the point where another handler plus its request type reads as an aside.
//!
//! **This is stricter than deleting the same messages one at a time**, and that
//! is a decision rather than an oversight. The single delete has no containment
//! rule at all - `escalation_guard` guards role edits, member moderation and
//! voice kicks, and has never guarded a message - so somebody holding
//! `MANAGE_MESSAGES` in a channel can delete an administrator's message there
//! today, one request at a time. Adding the guard here stops that being done
//! fifty at a time. Leaving the single path alone in the same change would be
//! the larger surprise, so the asymmetry is recorded in `TECHNICAL_DEBT.md`
//! rather than quietly resolved in either direction.
//!
//! The cap is what actually bounds this, not the rate-limit class. `Class::Write`
//! is flat-cost and generous by design; what keeps one request from wrecking a
//! channel is [`MAX_BULK_DELETE_IDS`], sized against the op stream rather than
//! against politeness - see its own doc.

use axum::Router;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::post;
use serde::Deserialize;

use super::AppState;
use super::error::ApiError;
use super::escalation::escalation_guard;
use super::extract::{Authed, Json, enforce};
use super::messages::parse_uuid;
use crate::hub::Event;
use crate::ids::{ChannelId, MessageId, UserId};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::BulkDeleteError;

/// Most ids one bulk delete may name.
///
/// Not a politeness limit. Every deleted message writes one op to the channel's
/// stream, and `OP_SNAPSHOT_GAP` is the point past which a client whose cursor
/// is behind is told to reset rather than catch up - which throws away that
/// channel's whole local cache. A cap three orders below it keeps any single
/// purge comfortably inside what a returning client can page through.
///
/// 64 is `MAX_REMOVE_IDS_PER_OP`'s number, taken deliberately: the canvas
/// already worked out that ids-in-a-frame arithmetic against the 4 KiB
/// WebSocket ceiling, and a second, differently-argued constant for the same
/// shape of problem would be a worse answer than reusing the one with its
/// reasoning written down.
pub const MAX_BULK_DELETE_IDS: usize = 64;

#[derive(Deserialize)]
struct BulkDeleteRequest {
    message_ids: Vec<String>,
}

pub fn router() -> Router<AppState> {
    Router::new().route(
        "/channels/{channel_id}/messages/bulk-delete",
        post(bulk_delete),
    )
}

async fn bulk_delete(
    Authed(ctx): Authed,
    parts: Parts,
    Path(channel_id): Path<String>,
    State(state): State<AppState>,
    Json(req): Json<BulkDeleteRequest>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);

    if req.message_ids.is_empty() {
        return Err(ApiError::BadRequest("no message ids given"));
    }
    if req.message_ids.len() > MAX_BULK_DELETE_IDS {
        return Err(ApiError::BadRequest("too many message ids"));
    }

    // Before anything else, so the route cannot answer whether a channel exists
    // to somebody who cannot see it - the masking rule decision 0011 sets.
    if !state
        .store
        .has_permission(ctx.user_id, channel_id, Permissions::VIEW_CHANNEL)
        .await?
    {
        return Err(ApiError::Forbidden);
    }
    if !state
        .store
        .has_permission(ctx.user_id, channel_id, Permissions::MANAGE_MESSAGES)
        .await?
    {
        return Err(ApiError::Forbidden);
    }

    let mut ids = Vec::with_capacity(req.message_ids.len());
    for raw in &req.message_ids {
        ids.push(MessageId(parse_uuid(raw)?));
    }

    let resolved = match state.store.message_authors_in(channel_id, &ids).await {
        Ok(found) => found,
        Err(BulkDeleteError::NotFound(_)) => {
            return Err(ApiError::NotFound("message not found"));
        }
        Err(BulkDeleteError::Internal(err)) => return Err(err.into()),
    };

    // Every author checked before the first row moves: an id this caller may
    // not delete must not leave an earlier one in the same request already gone.
    let caller_granted = state
        .store
        .granted_permissions_in_channel(ctx.user_id, channel_id)
        .await?;
    let mut subjects: Vec<UserId> = Vec::new();
    for (_, author_id) in &resolved {
        let Some(author_id) = author_id else { continue };
        if !subjects.contains(author_id) {
            subjects.push(*author_id);
        }
        if *author_id == ctx.user_id {
            continue;
        }
        let target_granted = state
            .store
            .granted_permissions_in_channel(*author_id, channel_id)
            .await?;
        escalation_guard(caller_granted, target_granted)?;
    }

    let outcome = state
        .store
        .bulk_delete_messages(channel_id, &ids, ctx.user_id, &subjects)
        .await?;

    // One event per message, carrying its own op seq: the client applies an op
    // only when its seq is exactly one past its cursor, so an aggregate frame
    // would make every connected client resync instead.
    for deleted in &outcome.deleted {
        state.hub.publish(Event::MessageDeleted {
            op_seq: Some(deleted.op_seq),
            channel_id,
            message_id: deleted.message_id,
        });
    }
    for hex in &outcome.freed_attachments {
        if let Err(err) = state.media.delete_attachment(hex).await {
            tracing::warn!(%hex, error = %err, "failed to remove an orphaned attachment file");
        }
    }

    Ok(StatusCode::NO_CONTENT)
}
