// SPDX-License-Identifier: AGPL-3.0-only
//! Read-state and bundled catch-up routes.
//!
//! `PUT /channels/{id}/read` advances the caller's last-read marker and returns
//! the fresh unread count; `GET` reads it back. `POST /sync` is the reconnect
//! path: a client sends its per-scope cursors in one request (so a reconnect
//! storm is one request per user, not one per channel) and gets back the
//! messages after each cursor, authorized per scope.
//!
//! The response is bounded three ways: each scope is capped, the whole response
//! is capped, and a scope whose cursor is very far behind returns `reset` rather
//! than a long backlog, telling the client to discard local state and re-fetch
//! that channel fresh over REST.

use std::collections::HashMap;

use axum::Router;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::routing::{get, post};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{AuthedLimited, Json, READ, WRITE};
use super::message_enrich::with_reactions;
use super::messages::{MessageDto, parse_uuid};
use super::sync_ops::{MessageOpDto, SYNC_RESPONSE_BYTES, ops_for_scope};
use crate::ids::ChannelId;
use crate::permissions::Permissions;

/// Sync bodies are a list of small cursors; cap the body accordingly.
const SYNC_BODY_LIMIT: usize = 64 * 1024;
/// Most scopes a single sync may ask about.
const MAX_SCOPES: usize = 200;
/// Most messages returned for one scope.
const PER_SCOPE_LIMIT: i64 = 100;
/// Most messages returned across the whole response.
const AGGREGATE_LIMIT: i64 = 500;
/// A cursor further behind than this returns `reset` instead of a backlog.
const SNAPSHOT_GAP: i64 = 1000;

/// The read-state and sync routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/channels/{channel_id}/read", get(get_read).put(put_read))
        .route("/sync", post(sync))
        .layer(DefaultBodyLimit::max(SYNC_BODY_LIMIT))
}

// --- Wire types ---

#[derive(Deserialize)]
struct MarkReadRequest {
    seq: i64,
}

#[derive(Serialize)]
struct ReadStateDto {
    last_read_seq: i64,
    unread: i64,
}

#[derive(Deserialize)]
struct SyncRequest {
    scopes: Vec<ScopeCursor>,
}

#[derive(Deserialize)]
struct ScopeCursor {
    channel_id: String,
    after_seq: i64,
    /// The message-op cursor, absent when the client holds none.
    ///
    /// Absent is what every older client sends and what a newer one sends
    /// before it has adopted a head. Both take the same branch, and a scope
    /// that carries none is never told to reset from an op gap.
    #[serde(default)]
    after_op_seq: Option<i64>,
}

#[derive(Serialize)]
struct SyncResponse {
    scopes: Vec<ScopeDelta>,
}

#[derive(Serialize)]
struct ScopeDelta {
    channel_id: String,
    messages: Vec<MessageDto>,
    /// More messages remain past what this response carried.
    has_more: bool,
    /// Either cursor was too far behind; discard local state and re-fetch.
    ///
    /// One flag rather than two, because the client's recovery is identical
    /// whichever cursor could not be answered. It is only ever set from an op
    /// gap for a scope whose request carried an op cursor.
    reset: bool,
    /// Empty whenever the request carried no op cursor, and empty when there
    /// is genuinely nothing.
    ops: Vec<MessageOpDto>,
    /// The head of this channel's op stream. Always present on this server,
    /// which is how a new client tells it from one that has no op stream.
    op_latest_seq: i64,
    ops_has_more: bool,
}

// --- Handlers ---

async fn get_read(
    AuthedLimited(ctx): AuthedLimited<READ>,
    Path(channel_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<ReadStateDto>, ApiError> {
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    if !state
        .store
        .has_permission(ctx.user_id, channel_id, Permissions::VIEW_CHANNEL)
        .await?
    {
        return Err(ApiError::Forbidden);
    }
    let last_read_seq = state.store.last_read_seq(ctx.user_id, channel_id).await?;
    let unread = state.store.unread_count(ctx.user_id, channel_id).await?;
    Ok(Json(ReadStateDto {
        last_read_seq,
        unread,
    }))
}

async fn put_read(
    AuthedLimited(ctx): AuthedLimited<WRITE>,
    Path(channel_id): Path<String>,
    State(state): State<AppState>,
    Json(req): Json<MarkReadRequest>,
) -> Result<Json<ReadStateDto>, ApiError> {
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    if req.seq < 0 {
        return Err(ApiError::BadRequest("seq must not be negative"));
    }
    if !state
        .store
        .has_permission(ctx.user_id, channel_id, Permissions::VIEW_CHANNEL)
        .await?
    {
        return Err(ApiError::Forbidden);
    }
    state
        .store
        .mark_read(ctx.user_id, channel_id, req.seq)
        .await?;
    let last_read_seq = state.store.last_read_seq(ctx.user_id, channel_id).await?;
    let unread = state.store.unread_count(ctx.user_id, channel_id).await?;
    Ok(Json(ReadStateDto {
        last_read_seq,
        unread,
    }))
}

/// Catches a client up across several channels at once, under a per-scope, an
/// aggregate and a snapshot-gap cap.
///
/// Deltas go through `with_reactions`, exactly as list and search do, rather
/// than a bare `MessageDto::from`. The bare conversion leaves `reactions`
/// empty, so a message that arrived by catch-up came back with no reactions at
/// all while the same message fetched by list carried them, and a client that
/// trusts its local store showed the difference.
async fn sync(
    AuthedLimited(ctx): AuthedLimited<WRITE>,
    State(state): State<AppState>,
    Json(req): Json<SyncRequest>,
) -> Result<Json<SyncResponse>, ApiError> {
    if req.scopes.len() > MAX_SCOPES {
        return Err(ApiError::BadRequest("too many scopes"));
    }

    // Collapse duplicate channels so a request padded with repeats cannot
    // multiply the per-scope database work.
    let cursors = dedupe_scopes(req.scopes);

    let mut scopes = Vec::new();
    let mut budget = AGGREGATE_LIMIT;
    let mut bytes = SYNC_RESPONSE_BYTES;
    for cursor in cursors {
        let channel_id = ChannelId(parse_uuid(&cursor.channel_id)?);
        // Silently skip scopes the caller cannot view, so sync never confirms a
        // hidden channel exists.
        if !state
            .store
            .has_permission(ctx.user_id, channel_id, Permissions::VIEW_CHANNEL)
            .await?
        {
            continue;
        }

        // Read after the permission check, never before it.
        let ops = ops_for_scope(&state, channel_id, cursor.after_op_seq, &mut bytes).await?;

        let latest = state.store.latest_message_seq(channel_id).await?;
        let (messages, has_more, message_reset) = if cursor.after_seq >= latest {
            (Vec::new(), false, false)
        } else if latest.saturating_sub(cursor.after_seq) > SNAPSHOT_GAP {
            (Vec::new(), true, true)
        } else {
            let limit = PER_SCOPE_LIMIT.min(budget);
            if limit <= 0 {
                // The aggregate budget is spent; report more remains here.
                (Vec::new(), true, false)
            } else {
                let mut rows = state
                    .store
                    .messages_since(channel_id, cursor.after_seq, limit + 1)
                    .await?;
                let has_more = rows.len() as i64 > limit;
                rows.truncate(limit as usize);
                budget -= rows.len() as i64;
                // `with_reactions`, never a bare `MessageDto::from`; see the
                // note on this function.
                let dtos = with_reactions(&state, ctx.user_id, rows).await?;
                for dto in &dtos {
                    bytes = bytes.saturating_sub(dto.wire_cost());
                }
                (dtos, has_more, false)
            }
        };

        scopes.push(ScopeDelta {
            channel_id: cursor.channel_id,
            messages,
            has_more,
            reset: message_reset || ops.reset,
            ops: ops.ops,
            op_latest_seq: ops.op_latest_seq,
            ops_has_more: ops.ops_has_more,
        });
    }

    Ok(Json(SyncResponse { scopes }))
}

/// Collapses repeated channels, keeping the cursor that asks for the most (the
/// smallest `after_seq`), so the request cannot be padded to inflate work.
fn dedupe_scopes(scopes: Vec<ScopeCursor>) -> Vec<ScopeCursor> {
    let mut deduped: Vec<ScopeCursor> = Vec::new();
    let mut index: HashMap<String, usize> = HashMap::new();
    for cursor in scopes {
        match index.get(&cursor.channel_id) {
            Some(&at) => deduped[at].after_seq = deduped[at].after_seq.min(cursor.after_seq),
            None => {
                index.insert(cursor.channel_id.clone(), deduped.len());
                deduped.push(cursor);
            }
        }
    }
    deduped
}
