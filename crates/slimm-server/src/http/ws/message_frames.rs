// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Building the `message.created`/`message.edited` wire frames, split out of
//! [`super::authorization::authorize`] when adding `mentions_me`'s own
//! per-connection lookup pushed that file past the 500-line hard ceiling.
//!
//! `Err(())` stands in for [`super::authorization::Authorization::Unknown`]:
//! a failed store read here is unresolved, not "no mention", the same
//! discipline `Event::ReactionsChanged` already follows in `authorization.rs`
//! for its own fresh-per-event store read.

use super::super::apps::AppSurfaceDto;
use super::super::message_dto::{CallDto, CodeRunDto};
use super::super::polls::PollDto;
use super::{AttachmentDto, MessageDto, frames::ServerFrame};
use crate::ids::UserId;
use crate::store::{
    AppSurface, AttachmentSummary, CodeRunSummary, ForwardSummary, Message, Poll, Store,
};

/// Everything about a freshly created message that the bare row cannot
/// express, bundled so [`created`] stays within the positional-parameter
/// limit. Every field is resolved once by the sender - see
/// [`crate::hub::Event::MessageCreated`] - rather than queried here per
/// subscriber: most messages launch no app and carry no poll, and this runs
/// once per delivered message per connection.
pub(super) struct MessageExtras {
    pub attachments: Vec<AttachmentSummary>,
    pub forwarded: Option<ForwardSummary>,
    pub app_surface: Option<AppSurface>,
    pub code_run: Option<CodeRunSummary>,
    pub poll: Option<Poll>,
}

/// The frame for a freshly sent message, with `mentions_me` resolved by one
/// point lookup against `message_id` for `viewer` - see
/// [`crate::store::Store::is_mentioned`] for why the live path cannot
/// instead read this off the broadcast event.
pub(super) async fn created(
    store: &Store,
    viewer: UserId,
    message: Message,
    extras: MessageExtras,
) -> Result<ServerFrame, ()> {
    let channel_id = message.channel_id.to_string();
    let seq = message.seq.0;
    let message_id = message.id;
    let mut dto = MessageDto::from(message);
    dto.attachments = extras
        .attachments
        .into_iter()
        .map(AttachmentDto::from)
        .collect();
    dto.forwarded = extras.forwarded.map(Into::into);
    // Without these an app or a poll arrives blank until the next cold read.
    dto.app_surface = extras.app_surface.map(AppSurfaceDto::from);
    dto.poll = extras.poll.map(PollDto::from);
    if let Some(run) = extras.code_run {
        dto.code_runs = vec![CodeRunDto {
            block_index: run.block_index,
            module_id: run.module_id,
            command: run.command,
            ok: run.ok,
            output: run.output,
            ran_by: run.ran_by.map(|u| u.to_string()),
            ran_at: run.ran_at,
        }];
    }
    dto.mentions_me = store
        .is_mentioned(message_id, viewer)
        .await
        .map_err(|_| ())?;
    // Without this a call arrives blank until the next cold read.
    dto.call = store
        .call_for_message(message_id)
        .await
        .map_err(|_| ())?
        .map(CallDto::from);
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
