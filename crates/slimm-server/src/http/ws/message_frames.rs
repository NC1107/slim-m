// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Building the `message.created`/`message.edited` wire frames, split out of
//! [`super::authorization::authorize`] when adding `mentions_me`'s own
//! per-connection lookup pushed that file past the 500-line hard ceiling.
//!
//! `Err(())` stands in for [`super::authorization::Authorization::Unknown`]:
//! a failed store read here is unresolved, not "no mention", the same
//! discipline `Event::ReactionsChanged` already follows in `authorization.rs`
//! for its own fresh-per-event store read.

use super::{AttachmentDto, MessageDto, frames::ServerFrame};
use crate::ids::UserId;
use crate::store::{AttachmentSummary, ForwardSummary, Message, Store};

/// The frame for a freshly sent message, with `mentions_me` resolved by one
/// point lookup against `message_id` for `viewer` - see
/// [`crate::store::Store::is_mentioned`] for why the live path cannot
/// instead read this off the broadcast event.
pub(super) async fn created(
    store: &Store,
    viewer: UserId,
    message: Message,
    attachments: Vec<AttachmentSummary>,
    forwarded: Option<ForwardSummary>,
) -> Result<ServerFrame, ()> {
    let channel_id = message.channel_id.to_string();
    let seq = message.seq.0;
    let message_id = message.id;
    let mut dto = MessageDto::from(message);
    dto.attachments = attachments.into_iter().map(AttachmentDto::from).collect();
    dto.forwarded = forwarded.map(Into::into);
    dto.mentions_me = store
        .is_mentioned(message_id, viewer)
        .await
        .map_err(|_| ())?;
    Ok(ServerFrame::MessageCreated {
        channel_id,
        seq,
        message: dto,
    })
}

/// [`created`]'s own sibling for an edit, which carries the message-op
/// stream's own `op_seq` rather than nothing extra.
pub(super) async fn edited(
    store: &Store,
    viewer: UserId,
    message: Message,
    op_seq: i64,
    forwarded: Option<ForwardSummary>,
) -> Result<ServerFrame, ()> {
    let channel_id = message.channel_id.to_string();
    let seq = message.seq.0;
    let message_id = message.id;
    let mut dto = MessageDto::from(message);
    dto.forwarded = forwarded.map(Into::into);
    dto.mentions_me = store
        .is_mentioned(message_id, viewer)
        .await
        .map_err(|_| ())?;
    Ok(ServerFrame::MessageEdited {
        channel_id,
        seq,
        op_seq: Some(op_seq),
        message: dto,
    })
}
