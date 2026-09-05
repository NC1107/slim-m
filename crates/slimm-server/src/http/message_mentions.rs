// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Resolving and persisting one message's mention set - the HTTP-layer glue
//! between [`crate::mentions::mentioned_viewers`] and
//! [`crate::store::Store::set_message_mentions`], shared by
//! `messages::send`, `messages::edit` and `polls::create` so a fresh send, a
//! content-changing edit and a poll's caption all resolve mentions the same
//! way instead of three near-identical inline blocks.

use super::AppState;
use crate::ids::{ChannelId, MessageId, UserId};

/// Resolves who `content` (written by `author_id` in `channel_id`) mentions
/// and stores the result against `message_id`, replacing whatever was there
/// before. Called before the caller's own `hub.publish`, so a connection the
/// live frame reaches can already answer `is_mentioned` for it; see
/// `store::message_mentions` and `http::ws::message_frames`.
///
/// `messages::edit` passes the message's own stored author here, never
/// `ctx.user_id`: a moderator's `MANAGE_MESSAGES` edit of someone else's
/// message must not gain that other author's `MENTION_EVERYONE` reach, and
/// only falls back to the editor once the author is already anonymized and
/// has no permission left to check at all.
pub(crate) async fn resolve_and_store(
    state: &AppState,
    channel_id: ChannelId,
    author_id: UserId,
    message_id: MessageId,
    content: &str,
) -> anyhow::Result<()> {
    let mentioned = crate::mentions::mentioned_viewers(
        &state.store,
        channel_id,
        author_id,
        content,
        &state.hub.presence(),
    )
    .await?;
    state
        .store
        .set_message_mentions(message_id, &mentioned)
        .await
}
