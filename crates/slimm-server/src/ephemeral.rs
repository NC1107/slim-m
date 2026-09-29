// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! A message only one member can see, sent by a bot and never stored.
//! See docs/decisions/0037-ephemeral-bot-messages.md.

use crate::ids::{ChannelId, MessageId, UserId};

/// How long after a member's message a bot may still answer it privately.
pub const ANCHOR_WINDOW_MS: i64 = 15 * 60 * 1000;

/// The most a channel keeps per recipient is a client concern; the server
/// holds nothing, so this is only the shape that crosses the hub.
#[derive(Debug, Clone)]
pub struct EphemeralMessage {
    pub id: MessageId,
    pub channel_id: ChannelId,
    pub author_id: UserId,
    pub author_display_name: String,
    pub content: String,
    pub in_reply_to_id: MessageId,
    pub created_at: i64,
}
