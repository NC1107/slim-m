// SPDX-License-Identifier: AGPL-3.0-only
//! Reaction routes: add and remove one emoji on one message.
//!
//! Both are idempotent, because the client that most needs them is the one on
//! a bad connection retrying. Reacting twice leaves one reaction; removing a
//! reaction that is not there succeeds, since the caller's intent ("this emoji
//! of mine is gone") already holds.
//!
//! The emoji is a path segment rather than a body, so the two verbs are a plain
//! PUT and DELETE on the same resource.

use axum::Router;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::put;

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, enforce};
use super::messages::parse_uuid;
use crate::hub::Event;
use crate::ids::MessageId;
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::ReactError;

/// Nothing here carries a body; the emoji is in the path.
const BODY_LIMIT: usize = 1024;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route(
            "/messages/{message_id}/reactions/{emoji}",
            put(add).delete(remove),
        )
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

/// Resolves the message and checks the caller may both see and react in its
/// channel. Returns the channel so the caller can publish to it.
///
/// Viewing is checked as well as reacting, because a reaction is otherwise a
/// probe: reacting to an id and seeing it succeed would confirm a message
/// exists in a channel the caller cannot read.
async fn authorize(
    state: &AppState,
    user_id: crate::ids::UserId,
    message_id: MessageId,
) -> Result<crate::ids::ChannelId, ApiError> {
    let Some(message) = state.store.message(message_id).await? else {
        return Err(ApiError::NotFound("no such message"));
    };
    let permissions = state
        .store
        .permissions_in_channel(user_id, message.channel_id)
        .await?;
    if !permissions.contains(Permissions::VIEW_CHANNEL) {
        // The same answer a missing message gets, so the two are not
        // distinguishable from outside.
        return Err(ApiError::NotFound("no such message"));
    }
    if !permissions.contains(Permissions::ADD_REACTIONS) {
        return Err(ApiError::Forbidden);
    }
    Ok(message.channel_id)
}

async fn add(
    Authed(ctx): Authed,
    parts: Parts,
    Path((message_id, emoji)): Path<(String, String)>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let message_id = MessageId(parse_uuid(&message_id)?);
    let channel_id = authorize(&state, ctx.user_id, message_id).await?;

    match state
        .store
        .add_reaction(message_id, ctx.user_id, &emoji)
        .await
    {
        Ok(()) => {}
        Err(ReactError::UnknownMessage) => return Err(ApiError::NotFound("no such message")),
        Err(ReactError::InvalidEmoji) => {
            return Err(ApiError::BadRequest("that is not a usable emoji"));
        }
        Err(ReactError::TooManyDistinctEmoji) => {
            return Err(ApiError::BadRequest(
                "this message already has as many different reactions as it can hold",
            ));
        }
        Err(ReactError::Internal(e)) => return Err(e.into()),
    }

    publish(&state, channel_id, message_id).await;
    Ok(StatusCode::NO_CONTENT)
}

async fn remove(
    Authed(ctx): Authed,
    parts: Parts,
    Path((message_id, emoji)): Path<(String, String)>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let message_id = MessageId(parse_uuid(&message_id)?);
    let channel_id = authorize(&state, ctx.user_id, message_id).await?;

    state
        .store
        .remove_reaction(message_id, ctx.user_id, &emoji)
        .await?;
    publish(&state, channel_id, message_id).await;
    Ok(StatusCode::NO_CONTENT)
}

/// Tells live connections the message's reactions changed.
///
/// The event carries the whole summary set rather than a delta, because a
/// client that missed an earlier frame would otherwise apply a delta to a state
/// it does not have and drift. The set is small and this is not a hot path.
///
/// `reacted` is deliberately absent from the broadcast: it differs per viewer,
/// and one connection must never be told what another user reacted with beyond
/// the public count. Each client re-derives its own toggled state.
async fn publish(state: &AppState, channel_id: crate::ids::ChannelId, message_id: MessageId) {
    // The viewer only decides the per-viewer `reacted` flag, which is dropped
    // below, so any id yields the same public counts.
    match state
        .store
        .reactions_for_message(message_id, crate::ids::UserId::generate())
        .await
    {
        Ok(summaries) => {
            state.hub.publish(Event::ReactionsChanged {
                channel_id,
                message_id,
                reactions: summaries.into_iter().map(|s| (s.emoji, s.count)).collect(),
            });
        }
        Err(err) => {
            // The write already succeeded; a failed fan-out means live clients
            // are briefly stale until their next fetch, which is not worth
            // failing the request over.
            tracing::warn!(error = %err, "reactions: could not load summaries to publish");
        }
    }
}
