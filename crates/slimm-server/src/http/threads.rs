// SPDX-License-Identifier: AGPL-3.0-only
//! Opening the thread hanging off a message: `POST
//! .../messages/{message_id}/thread`. Gated on the same VIEW_CHANNEL plus
//! SEND_MESSAGES a plain send needs in the parent channel, because starting a
//! thread is a way of sending, not a way of managing the channel - see
//! docs/decisions/0005-threads.md for why a thread is a channel with a parent
//! rather than a container of its own kind.

use axum::Router;
use axum::extract::{Path, State};
use axum::http::request::Parts;
use axum::routing::post;

use super::AppState;
use super::channels::ChannelDto;
use super::error::ApiError;
use super::extract::{Authed, Json, enforce};
use super::messages::parse_uuid;
use crate::hub::Event;
use crate::ids::{ChannelId, MessageId};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::OpenThreadError;

/// The thread route, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new().route(
        "/channels/{channel_id}/messages/{message_id}/thread",
        post(open),
    )
}

/// Opens (or reuses) the thread hanging off a message.
///
/// A nonexistent or unviewable channel answers identically, exactly like
/// `sendMessage`: this checks `VIEW_CHANNEL` and `SEND_MESSAGES` in the
/// parent channel and never asks the thread channel itself anything, since
/// it does not exist yet on the first call and inherits those bits from the
/// parent on every later one.
async fn open(
    Authed(ctx): Authed,
    parts: Parts,
    Path((channel_id, message_id)): Path<(String, String)>,
    State(state): State<AppState>,
) -> Result<Json<ChannelDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    let message_id = MessageId(parse_uuid(&message_id)?);

    let needed = Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES);
    if !state
        .store
        .has_permission(ctx.user_id, channel_id, needed)
        .await?
    {
        return Err(ApiError::Forbidden);
    }

    let thread = match state.store.open_thread(channel_id, message_id).await {
        Ok(thread) => thread,
        Err(OpenThreadError::UnknownMessage) => {
            return Err(ApiError::NotFound("message not found"));
        }
        Err(OpenThreadError::NestedThread) => {
            return Err(ApiError::BadRequest(
                "cannot open a thread on a message that is itself inside a thread",
            ));
        }
        Err(OpenThreadError::Internal(e)) => return Err(e.into()),
    };
    // A race loser or a reopen of an existing thread sends nothing new; see `OpenedThread::fresh`.
    if thread.fresh {
        state.hub.publish(Event::ThreadUpdated {
            channel_id,
            parent_message_id: message_id,
            thread_channel_id: thread.channel.id,
            reply_count: 0,
            last_reply_at: None,
        });
    }
    Ok(Json(thread.channel.into()))
}

/// Publishes a `ThreadUpdated` frame when `channel_id` is a thread's own
/// channel, so a bystander watching the parent sees the reply count move
/// live. Called from the message send path; best-effort, since the send it
/// rides on has already succeeded and must not be failed by this lookup.
pub(super) async fn notify_reply(state: &AppState, channel_id: ChannelId) {
    let parent = match state.store.thread_parent(channel_id).await {
        Ok(parent) => parent,
        Err(err) => {
            tracing::warn!(error = %err, "failed to resolve a thread's parent for a live update");
            return;
        }
    };
    let Some(parent) = parent else { return };
    let summary = match state
        .store
        .thread_summaries_for_messages(&[parent.parent_message_id])
        .await
    {
        Ok(rows) => rows.into_iter().next(),
        Err(err) => {
            tracing::warn!(error = %err, "failed to resolve a thread's reply summary for a live update");
            return;
        }
    };
    let Some((_, summary)) = summary else { return };
    state.hub.publish(Event::ThreadUpdated {
        channel_id: parent.parent_channel_id,
        parent_message_id: parent.parent_message_id,
        thread_channel_id: channel_id,
        reply_count: summary.reply_count,
        last_reply_at: summary.last_reply_at,
    });
}
