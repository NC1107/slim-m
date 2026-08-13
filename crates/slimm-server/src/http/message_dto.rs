// SPDX-License-Identifier: AGPL-3.0-only
//! The wire shape a message answers with, split out of [`super::messages`]
//! when that file crossed the 500-line hard ceiling again (it had already
//! been split once, for [`super::message_enrich`]). This is the type only;
//! every route that builds or enriches one still lives in `messages.rs` and
//! `message_enrich.rs`.

use serde::Serialize;

use super::polls::PollDto;
use crate::store::{AttachmentSummary, Message};

#[derive(Serialize)]
pub(crate) struct MessageDto {
    id: String,
    channel_id: String,
    author_id: Option<String>,
    /// Null once the author's account is anonymized, which is also when
    /// `author_id` goes null. Clients render their own fallback rather than
    /// being handed a server-invented placeholder.
    author_display_name: Option<String>,
    seq: i64,
    content: String,
    created_at: i64,
    edited_at: Option<i64>,
    /// The message this one replies to, or `null`. Only ever the id: the
    /// parent's own content, author and liveness are resolved by looking that
    /// id up like any other message, never copied onto this row, or a client
    /// caching this reply would go stale the moment the parent is edited or
    /// deleted with no way to notice.
    reply_to_id: Option<String>,
    /// The thread opened from this message, or `null` if none has been
    /// started yet. Always present as a key, the same "always there, empty
    /// or null means genuinely none" convention `poll` and `reactions`
    /// follow. Set by [`super::message_enrich::with_reactions`]'s batch
    /// lookup, never by this conversion: a message can only grow a thread
    /// after it already exists, so a freshly sent or edited one always
    /// carries `null` here, exactly like a fresh message's `poll`.
    pub(crate) thread_channel_id: Option<String>,
    /// Undeleted replies in this message's thread, or `null` if no thread
    /// has been started - same convention as `thread_channel_id`, and
    /// `null` whenever that field is `null`. Can be `0`: opening a thread
    /// creates its channel before the first reply lands in it. Batch-loaded
    /// alongside `thread_channel_id` by
    /// [`super::message_enrich::with_reactions`], never carried on `Message`
    /// itself.
    pub(crate) thread_reply_count: Option<i64>,
    /// When the thread's newest undeleted reply was sent, unix milliseconds,
    /// or `null` when `thread_reply_count` is `null` or `0`. Lets a client
    /// show "3 replies, last one yesterday" rather than just a count.
    pub(crate) thread_last_reply_at: Option<i64>,
    /// How many of the thread's live messages the caller has not yet read,
    /// or `null` when `thread_channel_id` is `null` - same convention as the
    /// other three thread fields. Genuinely `0` for a thread the caller has
    /// fully read, never omitted the way an unstarted thread's fields are.
    /// Batch-loaded alongside `thread_channel_id` by
    /// [`super::message_enrich::with_reactions`], from
    /// [`crate::store::Store::thread_unread_counts`] - the read-tracking
    /// every channel already has, surfaced here for the first time.
    pub(crate) thread_unread_count: Option<i64>,
    /// Empty unless the caller asked for a list, which is the only path that
    /// batch-loads them; a single echoed message carries none because it
    /// cannot have any yet.
    #[serde(default)]
    pub(crate) reactions: Vec<ReactionDto>,
    /// The poll this message carries, if any. Always present as a key (never
    /// omitted): `null` means this message is not a poll, the same "always
    /// there, empty or null means genuinely none" convention `reactions`
    /// already follows. Set by [`super::polls::attach_polls`], not by this
    /// conversion, since a bare `Message` has nowhere to read poll data from.
    pub(crate) poll: Option<PollDto>,
    /// Always present, empty when there are none - same convention as
    /// `reactions`. Unlike reactions and polls, a fresh send can carry these
    /// immediately (they are uploaded before the send, then referenced in
    /// it), so the send path reads them once and fills this in on both its
    /// own response and the live frame, rather than leaving it empty the way
    /// `reactions` is left empty for a message that cannot have any yet.
    #[serde(default)]
    pub(crate) attachments: Vec<AttachmentDto>,
}

/// One attachment as it appears on a message.
#[derive(Serialize, Clone)]
pub(crate) struct AttachmentDto {
    id: String,
    filename: String,
    content_type: String,
    size: i64,
}

impl From<AttachmentSummary> for AttachmentDto {
    fn from(a: AttachmentSummary) -> Self {
        Self {
            id: a.id,
            filename: a.filename,
            content_type: a.content_type,
            size: a.size,
        }
    }
}

/// One emoji on a message, with the asking user's own state.
#[derive(Serialize)]
pub(crate) struct ReactionDto {
    pub(crate) emoji: String,
    pub(crate) count: i64,
    /// Whether the caller reacted with this emoji, so the client can render the
    /// toggled state without a second request.
    pub(crate) reacted: bool,
}

impl MessageDto {
    /// Roughly what this row costs a `/sync` response, for the shared byte
    /// budget. The body dominates; the fixed addend stands in for the ids and
    /// timestamps around it rather than pretending to be exact.
    pub(super) fn wire_cost(&self) -> usize {
        self.content.len() + 128
    }
}

impl From<Message> for MessageDto {
    fn from(message: Message) -> Self {
        Self {
            id: message.id.to_string(),
            channel_id: message.channel_id.to_string(),
            author_id: message.author_id.map(|id| id.to_string()),
            author_display_name: message.author_display_name,
            seq: message.seq.0,
            content: message.content,
            created_at: message.created_at,
            edited_at: message.edited_at,
            reply_to_id: message.reply_to_id.map(|id| id.to_string()),
            thread_channel_id: None,
            thread_reply_count: None,
            thread_last_reply_at: None,
            thread_unread_count: None,
            reactions: Vec::new(),
            poll: None,
            attachments: Vec::new(),
        }
    }
}
