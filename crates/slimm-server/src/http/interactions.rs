// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! A member presses a bot's button, and the bot answers. Nothing about a press
//! is stored beyond one short-lived row. See
//! docs/decisions/0039-bot-message-buttons.md.

use std::sync::Arc;

use axum::Router;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::post;
use serde::{Deserialize, Serialize};

use super::AppState;
use super::ephemeral_anchor::Anchor;
use super::error::ApiError;
use super::extract::{Authed, Json, enforce};
use super::messages::parse_uuid;
use crate::components::{self, INTERACTION_WINDOW_MS};
use crate::hub::Event;
use crate::ids::{ChannelId, InteractionId, MessageId, UserId};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::{Interaction, now_ms};

pub fn routes() -> Router<AppState> {
    Router::new()
        .route(
            "/channels/{channelId}/messages/{messageId}/interactions",
            post(click),
        )
        .route(
            "/channels/{channelId}/interactions/{interactionId}/ack",
            post(ack),
        )
}

#[derive(Deserialize)]
struct ClickRequest {
    /// Chosen by the client, so a retried press is the same press.
    id: String,
    custom_id: String,
}

#[derive(Serialize)]
struct InteractionDto {
    id: String,
    created_at: i64,
}

/// A member presses a button on a bot's message. Any refusal that depends on
/// the message, the bot or the button is the same 404, so the route is not an
/// oracle for what a channel holds.
async fn click(
    Authed(ctx): Authed,
    Path((channel_id, message_id)): Path<(String, String)>,
    parts: Parts,
    State(state): State<AppState>,
    Json(req): Json<ClickRequest>,
) -> Result<Json<InteractionDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Interaction)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    let message_id = MessageId(parse_uuid(&message_id)?);
    let id = InteractionId(parse_uuid(&req.id)?);
    if !state
        .store
        .has_permission(ctx.user_id, channel_id, Permissions::VIEW_CHANNEL)
        .await?
        || state.store.is_bot(ctx.user_id).await?
    {
        return Err(ApiError::Forbidden);
    }
    const GONE: ApiError = ApiError::NotFound("message not found");
    let message = state
        .store
        .message(message_id)
        .await?
        .filter(|m| m.channel_id == channel_id)
        .ok_or(GONE)?;
    let bot_id = message.author_id.ok_or(GONE)?;
    let bot_can_hear = state.store.is_bot(bot_id).await?
        && state
            .store
            .has_permission(bot_id, channel_id, Permissions::VIEW_CHANNEL)
            .await?;
    if !bot_can_hear {
        return Err(GONE);
    }
    let rows = state.store.components_for_message(message_id).await?;
    if components::clickable(&rows, &req.custom_id).is_none() {
        return Err(GONE);
    }
    let display_name = state
        .store
        .user_profile(ctx.user_id)
        .await?
        .ok_or(ApiError::Forbidden)?
        .display_name;
    let fresh = Interaction {
        id,
        bot_id,
        clicker_id: ctx.user_id,
        channel_id,
        message_id,
        custom_id: req.custom_id,
        created_at: now_ms(),
        answered: false,
    };
    let (stored, is_new) = state
        .store
        .record_interaction(&fresh)
        .await?
        .ok_or(ApiError::Conflict("interaction id already used"))?;
    let dto = InteractionDto {
        id: stored.id.to_string(),
        created_at: stored.created_at,
    };
    if is_new {
        state.hub.publish(Event::InteractionCreated {
            interaction: Arc::new(stored),
            clicker_display_name: display_name,
        });
    }
    Ok(Json(dto))
}

/// The bot says it has seen the press and needs no visible answer, so the
/// clicker's button stops waiting.
async fn ack(
    Authed(ctx): Authed,
    Path((channel_id, interaction_id)): Path<(String, String)>,
    parts: Parts,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    let id = InteractionId(parse_uuid(&interaction_id)?);
    answer_from_bot(&state, ctx.user_id, channel_id, id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Marks a click answered on behalf of `bot_id` and tells the clicker, once.
/// Only the bot the click was addressed to may answer it.
pub(super) async fn answer_from_bot(
    state: &AppState,
    bot_id: UserId,
    channel_id: ChannelId,
    id: InteractionId,
) -> Result<Interaction, ApiError> {
    let interaction = own_interaction(state, bot_id, channel_id, id).await?;
    if state.store.mark_interaction_answered(id).await? {
        state.hub.publish(Event::InteractionAnswered {
            interaction: Arc::new(interaction.clone()),
        });
    }
    Ok(interaction)
}

/// The click `id` if it is still open, in `channel_id`, and addressed to `bot_id`.
async fn own_interaction(
    state: &AppState,
    bot_id: UserId,
    channel_id: ChannelId,
    id: InteractionId,
) -> Result<Interaction, ApiError> {
    state
        .store
        .interaction(id)
        .await?
        .filter(|i| i.bot_id == bot_id && i.channel_id == channel_id)
        .ok_or(ApiError::NotFound("interaction not found"))
}

/// A press as a private-reply anchor: the recipient is whoever pressed. `None`
/// when `id` is not a press at all, so the caller falls through to the
/// message-anchor rules. The per-anchor budget and the window are the same as
/// a message anchor's.
pub(super) async fn resolve_press(
    state: &AppState,
    bot_id: UserId,
    channel_id: ChannelId,
    id: InteractionId,
) -> Result<Option<Anchor>, ApiError> {
    let Some(interaction) = state.store.interaction(id).await? else {
        return Ok(None);
    };
    if interaction.bot_id != bot_id || interaction.channel_id != channel_id {
        return Err(ApiError::Forbidden);
    }
    Ok(Some(Anchor {
        id: id.0,
        recipient_id: interaction.clicker_id,
        in_reply_to_id: MessageId(id.0),
        expires_at: interaction.created_at + INTERACTION_WINDOW_MS,
        press: Some(id),
    }))
}
