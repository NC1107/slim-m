// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! What entitles a bot to answer a member privately: an anchor, turned into
//! the one recipient it addresses. Another kind of anchor (an interaction)
//! adds a resolver here and nothing else in the route changes.
//! See docs/decisions/0037-ephemeral-bot-messages.md.

use uuid::Uuid;

use super::AppState;
use super::error::ApiError;
use crate::ephemeral::{ANCHOR_WINDOW_MS, invokes_command};
use crate::ids::{ChannelId, InteractionId, MessageId, UserId};
use crate::store::Message;

/// A resolved anchor: who it entitles the bot to answer, and until when.
pub(super) struct Anchor {
    /// Keys the per-anchor budget.
    pub id: Uuid,
    pub recipient_id: UserId,
    pub in_reply_to_id: MessageId,
    pub expires_at: i64,
    /// Set when the anchor is a button press, which the answer then closes.
    pub press: Option<InteractionId>,
}

/// A person's recent message in this channel that is addressed to `bot`.
///
/// Every refusal is the same 403 or 404, so the route is not an oracle for a
/// message's mentions or replies.
pub(super) async fn resolve_message(
    state: &AppState,
    bot: UserId,
    channel_id: ChannelId,
    message_id: MessageId,
) -> Result<Anchor, ApiError> {
    let message = state
        .store
        .message(message_id)
        .await?
        .filter(|m| m.channel_id == channel_id)
        .ok_or(ApiError::NotFound("message not found"))?;
    let expires_at = message.created_at + ANCHOR_WINDOW_MS;
    if crate::store::now_ms() > expires_at {
        return Err(ApiError::Forbidden);
    }
    let recipient_id = message.author_id.ok_or(ApiError::Forbidden)?;
    // A bot answering a bot would be a channel nobody can see or moderate.
    if recipient_id == bot || state.store.is_bot(recipient_id).await? {
        return Err(ApiError::Forbidden);
    }
    if !addressed_to(state, bot, &message).await? {
        return Err(ApiError::Forbidden);
    }
    Ok(Anchor {
        id: message_id.0,
        recipient_id,
        in_reply_to_id: message_id,
        expires_at,
        press: None,
    })
}

/// What a bot names as the reason it may answer: a message, or a button press.
/// The two are separate ids and separate resolvers, so neither can stand in for the other.
pub(super) enum Target {
    Message(MessageId),
    Press(InteractionId),
}

pub(super) async fn resolve(
    state: &AppState,
    bot: UserId,
    channel_id: ChannelId,
    target: Target,
) -> Result<Anchor, ApiError> {
    match target {
        Target::Message(id) => resolve_message(state, bot, channel_id, id).await,
        Target::Press(id) => super::interactions::resolve_press(state, bot, channel_id, id).await,
    }
}

/// Whether the message mentions the bot, replies to one of its messages, or
/// invokes a command it registered.
///
/// A mention is read from `message_mentions`, which also holds the expansion
/// of an `@everyone` or `@here` from someone allowed to send one; that is a
/// deliberate act by a person holding that permission, and it is the one way
/// a message not aimed at this bot alone still qualifies.
async fn addressed_to(state: &AppState, bot: UserId, message: &Message) -> Result<bool, ApiError> {
    if state.store.is_mentioned(message.id, bot).await? {
        return Ok(true);
    }
    if let Some(parent_id) = message.reply_to_id {
        let parent = state.store.message(parent_id).await?;
        if parent.is_some_and(|p| p.author_id == Some(bot)) {
            return Ok(true);
        }
    }
    let Some(registration) = state.store.bot_commands(bot).await? else {
        return Ok(false);
    };
    Ok(invokes_command(
        &message.content,
        &registration.prefix,
        registration.commands.iter().map(|c| c.name.as_str()),
    ))
}
