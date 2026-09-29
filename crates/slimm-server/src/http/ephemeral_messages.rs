// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! A bot answers one member privately. Nothing is stored: the message goes
//! out over the hub to that member's own connections and is gone on reload.
//! See docs/decisions/0037-ephemeral-bot-messages.md.

use axum::Router;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::request::Parts;
use axum::routing::post;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, Json, enforce};
use super::messages::{parse_uuid, validate_content};
use crate::ephemeral::{ANCHOR_WINDOW_MS, EphemeralMessage};
use crate::hub::Event;
use crate::ids::{ChannelId, MessageId};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use std::sync::Arc;

const BODY_LIMIT: usize = 16 * 1024;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route(
            "/channels/{channelId}/ephemeral-messages",
            post(send_ephemeral),
        )
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

#[derive(Deserialize)]
struct SendEphemeralRequest {
    /// The member's own message being answered; its author is the recipient.
    in_reply_to_id: String,
    content: String,
}

/// The wire shape of an ephemeral message, on the REST reply and the live frame.
#[derive(Serialize)]
pub(crate) struct EphemeralMessageDto {
    id: String,
    channel_id: String,
    author_id: String,
    author_display_name: String,
    content: String,
    in_reply_to_id: String,
    created_at: i64,
}

impl From<&EphemeralMessage> for EphemeralMessageDto {
    fn from(m: &EphemeralMessage) -> Self {
        Self {
            id: m.id.to_string(),
            channel_id: m.channel_id.to_string(),
            author_id: m.author_id.to_string(),
            author_display_name: m.author_display_name.clone(),
            content: m.content.clone(),
            in_reply_to_id: m.in_reply_to_id.to_string(),
            created_at: m.created_at,
        }
    }
}

/// Only a bot, and only to the author of a recent message in the channel, so a
/// bot can answer a member who spoke to it and cannot reach anyone else. Every
/// refusal that would reveal another account's state is the same 403 or 404.
async fn send_ephemeral(
    Authed(ctx): Authed,
    Path(channel_id): Path<String>,
    parts: Parts,
    State(state): State<AppState>,
    Json(req): Json<SendEphemeralRequest>,
) -> Result<Json<EphemeralMessageDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    let anchor_id = MessageId(parse_uuid(&req.in_reply_to_id)?);
    let content = validate_content(&req.content, false)?;
    if !state.store.is_bot(ctx.user_id).await? {
        return Err(ApiError::Forbidden);
    }
    let needed = Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES);
    if !state
        .store
        .has_permission(ctx.user_id, channel_id, needed)
        .await?
    {
        return Err(ApiError::Forbidden);
    }
    let anchor = state
        .store
        .message(anchor_id)
        .await?
        .filter(|m| m.channel_id == channel_id)
        .ok_or(ApiError::NotFound("message not found"))?;
    if crate::store::now_ms() - anchor.created_at > ANCHOR_WINDOW_MS {
        return Err(ApiError::Forbidden);
    }
    let recipient_id = anchor.author_id.ok_or(ApiError::Forbidden)?;
    // A bot answering another bot would be a channel nobody can moderate.
    if recipient_id == ctx.user_id || state.store.is_bot(recipient_id).await? {
        return Err(ApiError::Forbidden);
    }
    if !state
        .store
        .has_permission(recipient_id, channel_id, Permissions::VIEW_CHANNEL)
        .await?
    {
        return Err(ApiError::Forbidden);
    }
    let author = state
        .store
        .user_profile(ctx.user_id)
        .await?
        .ok_or(ApiError::Forbidden)?;
    let message = Arc::new(EphemeralMessage {
        id: MessageId(Uuid::now_v7()),
        channel_id,
        author_id: ctx.user_id,
        author_display_name: author.display_name,
        content: content.to_owned(),
        in_reply_to_id: anchor_id,
        created_at: crate::store::now_ms(),
    });
    let dto = EphemeralMessageDto::from(message.as_ref());
    state.hub.publish(Event::EphemeralMessage {
        recipient_id,
        message,
    });
    Ok(Json(dto))
}
