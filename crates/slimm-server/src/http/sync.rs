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
use super::extract::{Authed, AuthedLimited, Json, WRITE};
use super::messages::{MessageDto, parse_uuid, with_reactions};
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
    /// The cursor was too far behind; discard local state and re-fetch fresh.
    reset: bool,
}

// --- Handlers ---

async fn get_read(
    Authed(ctx): Authed,
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

        let latest = state.store.latest_message_seq(channel_id).await?;
        let delta = if cursor.after_seq >= latest {
            ScopeDelta {
                channel_id: cursor.channel_id,
                messages: Vec::new(),
                has_more: false,
                reset: false,
            }
        } else if latest.saturating_sub(cursor.after_seq) > SNAPSHOT_GAP {
            ScopeDelta {
                channel_id: cursor.channel_id,
                messages: Vec::new(),
                has_more: true,
                reset: true,
            }
        } else {
            let limit = PER_SCOPE_LIMIT.min(budget);
            if limit <= 0 {
                // The aggregate budget is spent; report more remains here.
                ScopeDelta {
                    channel_id: cursor.channel_id,
                    messages: Vec::new(),
                    has_more: true,
                    reset: false,
                }
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
                ScopeDelta {
                    channel_id: cursor.channel_id,
                    messages: with_reactions(&state, ctx.user_id, rows).await?,
                    has_more,
                    reset: false,
                }
            }
        };
        scopes.push(delta);
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
