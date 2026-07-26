// SPDX-License-Identifier: AGPL-3.0-only
//! Direct-message conversations: listing the caller's own, and opening (or
//! returning) the one with another user.
//!
//! A DM is a channel under the hood (kind `dm`), so once one is open, every
//! other message operation - send, list, edit, delete, react, search, mark
//! read, sync, and the WebSocket fan-out - already works against it through
//! the ordinary `/channels/{channelId}/...` routes with no code of its own:
//! see `crate::store::dms` for why that channel's permissions do not run
//! through the deployment's role/overwrite evaluator. This module only
//! covers what is specific to a DM rather than any channel: discovering the
//! conversation list, and turning a target user id into a channel id.

use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::request::Parts;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::Serialize;

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, enforce};
use super::messages::parse_uuid;
use crate::ids::UserId;
use crate::ratelimit::Class;
use crate::store::{DmConversation, OpenDmError, User};

const BODY_LIMIT: usize = 1024;

/// The direct-message routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/dms", get(list))
        .route("/dms/{user_id}", post(open))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

// ---------------------------------------------------------------------------
// Wire types
// ---------------------------------------------------------------------------

#[derive(Serialize)]
struct DmConversationDto {
    channel_id: String,
    user: ParticipantDto,
    unread: i64,
    created_at: i64,
}

/// The other participant's public profile. The same narrow shape
/// `/users/{userId}` returns, redeclared here rather than shared: the two
/// modules have no reason to stay in lockstep beyond happening to agree on
/// what a public profile looks like today.
#[derive(Serialize)]
struct ParticipantDto {
    id: String,
    username: String,
    display_name: String,
    created_at: i64,
}

impl From<User> for ParticipantDto {
    fn from(user: User) -> Self {
        Self {
            id: user.id.to_string(),
            username: user.username,
            display_name: user.display_name,
            created_at: user.created_at,
        }
    }
}

impl From<DmConversation> for DmConversationDto {
    fn from(conversation: DmConversation) -> Self {
        Self {
            channel_id: conversation.channel_id.to_string(),
            user: conversation.other.into(),
            unread: conversation.unread,
            created_at: conversation.created_at,
        }
    }
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

/// Lists the caller's DM conversations, most recently active first.
async fn list(
    Authed(ctx): Authed,
    State(state): State<AppState>,
) -> Result<Json<Vec<DmConversationDto>>, ApiError> {
    let conversations = state.store.list_dm_conversations(ctx.user_id).await?;
    Ok(Json(
        conversations
            .into_iter()
            .map(DmConversationDto::from)
            .collect(),
    ))
}

/// Opens (or returns) the DM channel with another user.
///
/// Idempotent and race-safe on the store side (see
/// [`crate::store::Store::open_dm`]), so two clients opening the same pair at
/// once converge on one channel rather than creating two.
async fn open(
    Authed(ctx): Authed,
    parts: Parts,
    Path(user_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<DmConversationDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let target = UserId(parse_uuid(&user_id)?);

    let channel = match state.store.open_dm(ctx.user_id, target).await {
        Ok(channel) => channel,
        Err(OpenDmError::SameUser) => {
            return Err(ApiError::BadRequest("cannot open a DM with yourself"));
        }
        Err(OpenDmError::UserNotFound) => return Err(ApiError::NotFound("user not found")),
        // The same answer whichever direction blocked, so a caller learns
        // only that the DM is refused, never who blocked whom.
        Err(OpenDmError::Blocked) => return Err(ApiError::Forbidden),
        Err(OpenDmError::Internal(e)) => return Err(e.into()),
    };

    let other = state
        .store
        .user_profile(target)
        .await?
        .ok_or(ApiError::NotFound("user not found"))?;
    let unread = state.store.unread_count(ctx.user_id, channel.id).await?;
    Ok(Json(DmConversationDto {
        channel_id: channel.id.to_string(),
        user: other.into(),
        unread,
        created_at: channel.created_at,
    }))
}
