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
        Ok(channel) => channel,
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
    Ok(Json(thread.into()))
}
