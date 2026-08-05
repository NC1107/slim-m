// SPDX-License-Identifier: AGPL-3.0-only
//! The wire envelope: every frame shape the WebSocket sends or accepts.
//!
//! Split out of `super` (the connect/authenticate/authorize/serve loop) once
//! that file reached the 500-line hard ceiling; the two halves were already
//! marked apart by their own `// --- Envelope ---` / `// --- Connection ---`
//! section comments before this existed.

use serde::{Deserialize, Serialize};

use crate::http::canvas::CanvasObjectDto;
use crate::http::channels::ChannelDto;
use crate::http::messages::MessageDto;

#[derive(Serialize)]
#[serde(tag = "type")]
pub(super) enum ServerFrame {
    #[serde(rename = "hello")]
    Hello { protocol: u32 },
    #[serde(rename = "message.created")]
    MessageCreated {
        channel_id: String,
        seq: i64,
        message: MessageDto,
    },
    #[serde(rename = "message.edited")]
    MessageEdited {
        channel_id: String,
        /// The *message's* order key, unmoved by an edit. Not `op_seq`.
        seq: i64,
        #[serde(skip_serializing_if = "Option::is_none")]
        op_seq: Option<i64>,
        message: MessageDto,
    },
    #[serde(rename = "message.deleted")]
    MessageDeleted {
        channel_id: String,
        message_id: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        op_seq: Option<i64>,
    },
    #[serde(rename = "reactions.changed")]
    ReactionsChanged {
        channel_id: String,
        message_id: String,
        reactions: Vec<ReactionCountDto>,
    },
    #[serde(rename = "thread.updated")]
    ThreadUpdated {
        channel_id: String,
        parent_message_id: String,
        thread_channel_id: String,
        reply_count: i64,
        #[serde(skip_serializing_if = "Option::is_none")]
        last_reply_at: Option<i64>,
    },
    #[serde(rename = "message.pinned")]
    MessagePinned {
        channel_id: String,
        message_id: String,
        pinned_by: Option<String>,
        pinned_at: i64,
    },
    #[serde(rename = "message.unpinned")]
    MessageUnpinned {
        channel_id: String,
        message_id: String,
    },
    #[serde(rename = "poll.voted")]
    PollVoted {
        channel_id: String,
        message_id: String,
        options: Vec<PollOptionCountDto>,
    },
    #[serde(rename = "presence.changed")]
    PresenceChanged { user_id: String, status: String },
    #[serde(rename = "member.timeout")]
    MemberTimeoutChanged { user_id: String, until: Option<i64> },
    #[serde(rename = "member.removed")]
    MemberRemoved { user_id: String },
    #[serde(rename = "profile.changed")]
    ProfileChanged { user_id: String },
    #[serde(rename = "typing.started")]
    TypingStarted { channel_id: String, user_id: String },
    #[serde(rename = "typing.stopped")]
    TypingStopped { channel_id: String, user_id: String },
    #[serde(rename = "role.changed")]
    RoleChanged { role_id: String },
    #[serde(rename = "member.role_changed")]
    MemberRoleChanged { user_id: String, role_id: String },
    #[serde(rename = "channel.created")]
    ChannelCreated { channel: ChannelDto },
    #[serde(rename = "channel.updated")]
    ChannelUpdated { channel: ChannelDto },
    #[serde(rename = "channel.deleted")]
    ChannelDeleted { channel_id: String },
    #[serde(rename = "overwrite.changed")]
    OverwriteChanged { channel_id: String },
    #[serde(rename = "category.changed")]
    CategoryChanged,
    #[serde(rename = "voice.activity")]
    VoiceActivityChanged { channel_id: String },
    #[serde(rename = "canvas.object.placed")]
    CanvasObjectPlaced {
        channel_id: String,
        seq: i64,
        object: CanvasObjectDto,
    },
    #[serde(rename = "canvas.objects.removed")]
    CanvasObjectsRemoved {
        channel_id: String,
        seq: i64,
        op_id: String,
        object_ids: Vec<String>,
    },
    #[serde(rename = "canvas.cleared")]
    CanvasCleared {
        channel_id: String,
        seq: i64,
        op_id: String,
        before_seq: i64,
    },
    #[serde(rename = "canvas.objects.restored")]
    CanvasObjectsRestored {
        channel_id: String,
        seq: i64,
        op_id: String,
        object_ids: Vec<String>,
    },
    #[serde(rename = "canvas.cursor.moved")]
    CanvasCursorMoved {
        channel_id: String,
        user_id: String,
        x: f64,
        y: f64,
    },
    #[serde(rename = "pong")]
    Pong,
    #[serde(rename = "error")]
    Error { message: String },
}

/// One emoji and how many people used it. Public counts only: what the asking
/// user reacted with is per viewer and never broadcast.
#[derive(Serialize)]
pub(crate) struct ReactionCountDto {
    pub(super) emoji: String,
    pub(super) count: i64,
}

/// One poll option and its current public vote count. Never carries who cast
/// a vote, only the option and its tally.
#[derive(Serialize)]
pub(crate) struct PollOptionCountDto {
    pub(super) position: i64,
    pub(super) votes: i64,
}

#[derive(Deserialize)]
#[serde(tag = "type")]
pub(super) enum ClientFrame {
    #[serde(rename = "hello")]
    Hello { ticket: String, protocol: u32 },
    #[serde(rename = "ping")]
    Ping,
    /// A typing refresh. Rate-limited and authorized like any other channel
    /// event (view plus send); see [`super::signals::handle_typing`]. There is
    /// no explicit "stop" frame: the state lapses on its own without a refresh.
    #[serde(rename = "typing")]
    Typing { channel_id: String },
    /// A pointer position on a channel's canvas. Rate-limited and authorized
    /// the same bar the canvas HTTP routes use (view plus `USE_CANVAS`); see
    /// [`super::signals::handle_canvas_cursor`]. No "stop" frame either, for
    /// the reason [`crate::hub::Event::CanvasCursorMoved`] gives.
    #[serde(rename = "canvas.cursor")]
    CanvasCursor { channel_id: String, x: f64, y: f64 },
}
