// SPDX-License-Identifier: AGPL-3.0-only
//! Message HTTP routes: send, list, and edit, each authorized server-side
//! through the permission evaluator.
//!
//! Sends are idempotent by the client-supplied message id, so an at-least-once
//! client that retries never duplicates. Every handler checks permissions in the
//! target channel before touching the store: view to read, view plus send to
//! post, and authorship or manage-messages to edit.

use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::request::Parts;
use axum::routing::{get, patch};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, enforce};
use crate::hub::Event;
use crate::ids::{ChannelId, MessageId};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::Message;

/// Message bodies carry one text field; cap it generously but bounded.
const MESSAGE_BODY_LIMIT: usize = 64 * 1024;
/// Longest a single message may be, in characters.
const MESSAGE_MAX_CHARS: usize = 4000;
/// Default and maximum page sizes for history.
const DEFAULT_LIMIT: i64 = 50;
const MAX_LIMIT: i64 = 100;

/// The message routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/channels/{channel_id}/messages", get(list).post(send))
        .route("/channels/{channel_id}/messages/{message_id}", patch(edit))
        .layer(DefaultBodyLimit::max(MESSAGE_BODY_LIMIT))
}

// ---------------------------------------------------------------------------
// Wire types
// ---------------------------------------------------------------------------

#[derive(Serialize)]
pub(crate) struct MessageDto {
    id: String,
    channel_id: String,
    author_id: Option<String>,
    seq: i64,
    content: String,
    created_at: i64,
    edited_at: Option<i64>,
}

impl From<Message> for MessageDto {
    fn from(message: Message) -> Self {
        Self {
            id: message.id.to_string(),
            channel_id: message.channel_id.to_string(),
            author_id: message.author_id.map(|id| id.to_string()),
            seq: message.seq.0,
            content: message.content,
            created_at: message.created_at,
            edited_at: message.edited_at,
        }
    }
}

#[derive(Deserialize)]
struct SendRequest {
    /// Client-generated UUID (v7 preferred) that makes the send idempotent.
    id: String,
    content: String,
}

#[derive(Deserialize)]
struct EditRequest {
    content: String,
}

#[derive(Deserialize)]
struct ListParams {
    before: Option<i64>,
    limit: Option<i64>,
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

async fn send(
    Authed(ctx): Authed,
    Path(channel_id): Path<String>,
    parts: Parts,
    State(state): State<AppState>,
    Json(req): Json<SendRequest>,
) -> Result<Json<MessageDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);

    // A nonexistent channel grants no permissions, so this refuses both "you
    // cannot post here" and "no such channel" identically, revealing neither.
    let needed = Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES);
    if !state
        .store
        .has_permission(ctx.user_id, channel_id, needed)
        .await?
    {
        return Err(ApiError::Forbidden);
    }

    let content = validate_content(&req.content)?;
    let id = MessageId(parse_uuid(&req.id)?);
    let message = state
        .store
        .send_message(channel_id, ctx.user_id, id, content)
        .await?;
    state.hub.publish(Event::MessageCreated(message.clone()));

    // The message is already committed and its response is already on the
    // way; this only ever makes a cheap in-memory decision here, handing any
    // actual push work to a detached background task, so a relay outage can
    // never turn this successful send into an error.
    state.push.notify_message(
        state.store.clone(),
        channel_id,
        ctx.user_id,
        message.id,
        message.seq,
    );

    Ok(Json(message.into()))
}

async fn list(
    Authed(ctx): Authed,
    Path(channel_id): Path<String>,
    Query(params): Query<ListParams>,
    State(state): State<AppState>,
) -> Result<Json<Vec<MessageDto>>, ApiError> {
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    if !state
        .store
        .has_permission(ctx.user_id, channel_id, Permissions::VIEW_CHANNEL)
        .await?
    {
        return Err(ApiError::Forbidden);
    }

    let limit = params.limit.unwrap_or(DEFAULT_LIMIT).clamp(1, MAX_LIMIT);
    let messages = state
        .store
        .list_messages(channel_id, params.before, limit)
        .await?;
    Ok(Json(messages.into_iter().map(MessageDto::from).collect()))
}

async fn edit(
    Authed(ctx): Authed,
    Path((channel_id, message_id)): Path<(String, String)>,
    State(state): State<AppState>,
    Json(req): Json<EditRequest>,
) -> Result<Json<MessageDto>, ApiError> {
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    let message_id = MessageId(parse_uuid(&message_id)?);

    // Not being able to see the channel hides whether the message exists.
    if !state
        .store
        .has_permission(ctx.user_id, channel_id, Permissions::VIEW_CHANNEL)
        .await?
    {
        return Err(ApiError::Forbidden);
    }

    let message = state
        .store
        .message(message_id)
        .await?
        .filter(|m| m.channel_id == channel_id)
        .ok_or(ApiError::NotFound("message not found"))?;

    // Editing your own message is allowed; editing another's needs manage rights.
    let is_author = message.author_id == Some(ctx.user_id);
    if !is_author
        && !state
            .store
            .has_permission(ctx.user_id, channel_id, Permissions::MANAGE_MESSAGES)
            .await?
    {
        return Err(ApiError::Forbidden);
    }

    let content = validate_content(&req.content)?;
    let updated = state
        .store
        .edit_message(message_id, content)
        .await?
        .ok_or(ApiError::NotFound("message not found"))?;
    state.hub.publish(Event::MessageEdited(updated.clone()));
    Ok(Json(updated.into()))
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

fn validate_content(content: &str) -> Result<&str, ApiError> {
    if content.trim().is_empty() {
        return Err(ApiError::BadRequest("message content must not be empty"));
    }
    if content.chars().count() > MESSAGE_MAX_CHARS {
        return Err(ApiError::BadRequest("message content is too long"));
    }
    Ok(content)
}

pub(crate) fn parse_uuid(value: &str) -> Result<Uuid, ApiError> {
    Uuid::parse_str(value).map_err(|_| ApiError::BadRequest("invalid uuid"))
}
