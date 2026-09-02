// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The wire shape of a forwarded message, and the two ends that produce it:
//! resolving an origin at send time, and attaching it to a page of messages
//! on the way out.
//!
//! Its own module rather than a section of [`super::messages`], which is
//! already within seventy lines of the hard file ceiling, and because the
//! feature reads better in one piece than split across the send route, the
//! DTO and the enricher.
//!
//! Nothing here is reader-dependent, which is deliberate. An earlier shape
//! masked the origin's channel name for readers who could not see that
//! channel, and that cannot be done on the live path: `message.created` is
//! authorized per subscriber, so a masked field would mean a permission
//! query per recipient per forwarded message. Sending no name at all is both
//! cheaper and stricter - the client already holds its own channel list, so
//! it resolves a name it is entitled to and shows no origin for one it is
//! not. A name the reader cannot see never leaves the server.

use std::collections::HashMap;

use serde::Serialize;

use super::AppState;
use super::error::ApiError;
use crate::ids::{MessageId, UserId};
use crate::permissions::Permissions;
use crate::store::{ForwardOrigin, ForwardSummary};

/// What a message was forwarded from, or absent on a message that forwards
/// nothing.
///
/// A snapshot taken when the forward was sent, not a live read, so it stays
/// answerable once the original is edited or deleted.
#[derive(Serialize, Clone)]
pub(crate) struct ForwardedDto {
    /// The original, for a client that wants to jump to it. An id the reader
    /// cannot reach is an id they cannot resolve either: it names no channel
    /// in their own list, so the jump is simply not offered.
    pub message_id: String,
    pub channel_id: String,
    /// The original's author. Null once that account is anonymized, the same
    /// convention `author_id` follows on a message.
    pub author_id: Option<String>,
    pub author_display_name: Option<String>,
    /// Lets a client build the author's avatar URL without a second lookup,
    /// and bust its cache when they change it.
    pub author_avatar_updated_at: Option<i64>,
    /// When the original was sent, unix milliseconds - not when it was
    /// forwarded, which is the carrying message's own `created_at`.
    pub created_at: i64,
    /// What the original said when it was forwarded. A later edit to the
    /// original does not rewrite this; see the migration for why.
    pub content: String,
}

impl From<ForwardSummary> for ForwardedDto {
    fn from(summary: ForwardSummary) -> Self {
        Self {
            message_id: summary.origin.message_id.to_string(),
            channel_id: summary.origin.channel_id.to_string(),
            author_id: summary.origin.author_id.map(|id| id.to_string()),
            author_display_name: summary.author_display_name,
            author_avatar_updated_at: summary.author_avatar_updated_at,
            created_at: summary.origin.created_at,
            content: summary.origin.content,
        }
    }
}

/// Resolves the message a send says it is forwarding, refusing anything the
/// sender cannot legitimately pass on.
///
/// A message the sender cannot see is refused as a bad target rather than a
/// forbidden one, so this cannot be used to probe whether a given id exists
/// in a channel they have no access to - the same stance the send route
/// takes on a channel that does not exist.
pub(crate) async fn resolve(
    state: &AppState,
    sender: UserId,
    origin_id: MessageId,
) -> Result<ForwardOrigin, ApiError> {
    let invalid = ApiError::BadRequest("forwarded_from_id must name a live message you can see");
    let Some(origin) = state.store.forward_origin(origin_id).await? else {
        return Err(invalid);
    };
    if !state
        .store
        .has_permission(sender, origin.channel_id, Permissions::VIEW_CHANNEL)
        .await?
    {
        return Err(invalid);
    }
    Ok(origin)
}

/// Batch-loads the forward carried by each message on a page, keyed by the
/// id of the message carrying it.
///
/// One query for the page, and none at all when nothing on it is a forward,
/// which is the ordinary case.
pub(crate) async fn for_messages(
    state: &AppState,
    message_ids: &[MessageId],
) -> anyhow::Result<HashMap<MessageId, ForwardedDto>> {
    Ok(state
        .store
        .forwards_for_messages(message_ids)
        .await?
        .into_iter()
        .map(|(message_id, summary)| (message_id, summary.into()))
        .collect())
}
