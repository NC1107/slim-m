// SPDX-License-Identifier: AGPL-3.0-only
//! Turning a page of stored messages into the DTOs every read route answers
//! with, reactions and polls attached.
//!
//! Split out of [`super::messages`] when that file crossed the 500-line hard
//! ceiling. Its own file rather than a section of that one because it belongs
//! to no single route: list, full-text search, sync and the pinned-message
//! list all enrich a page the same way, and doing it per route is how the
//! `/sync` deltas once came back with an empty `reactions` array while the
//! same message fetched by list carried them.

use super::AppState;
use super::messages::{AttachmentDto, MessageDto, ReactionDto};
use crate::ids::{MessageId, UserId};
use crate::store::Message;

/// Batch-attaches each message's reaction summary and, if it carries one,
/// its poll, to its DTO - in a fixed small number of queries rather than one
/// per row, which only bites once a channel has real traffic. Shared by
/// [`list`], the full-text search route, sync, and the pinned-message list,
/// which all enrich a page of messages the same way.
pub(crate) async fn with_reactions(
    state: &AppState,
    viewer: UserId,
    messages: Vec<Message>,
) -> anyhow::Result<Vec<MessageDto>> {
    let ids: Vec<MessageId> = messages.iter().map(|m| m.id).collect();
    let mut by_message = state.store.reactions_for_messages(&ids, viewer).await?;
    let mut attachments_by_message = state.store.attachments_for_messages(&ids).await?;
    let mut threads_by_message = state.store.thread_summaries_for_messages(&ids).await?;

    let mut dtos: Vec<MessageDto> = Vec::with_capacity(messages.len());
    for message in messages {
        let id = message.id;
        let mut dto = MessageDto::from(message);
        if let Some(pos) = by_message.iter().position(|(mid, _)| *mid == id) {
            let (_, summaries) = by_message.swap_remove(pos);
            dto.reactions = summaries
                .into_iter()
                .map(|s| ReactionDto {
                    emoji: s.emoji,
                    count: s.count,
                    reacted: s.reacted,
                })
                .collect();
        }
        if let Some(pos) = attachments_by_message
            .iter()
            .position(|(mid, _)| *mid == id)
        {
            let (_, summaries) = attachments_by_message.swap_remove(pos);
            dto.attachments = summaries.into_iter().map(AttachmentDto::from).collect();
        }
        if let Some(pos) = threads_by_message.iter().position(|(mid, _)| *mid == id) {
            let (_, summary) = threads_by_message.swap_remove(pos);
            dto.thread_channel_id = Some(summary.channel_id.to_string());
            dto.thread_reply_count = Some(summary.reply_count);
            dto.thread_last_reply_at = summary.last_reply_at;
        }
        dtos.push(dto);
    }
    // Paired positionally: the loop above pushes one `dtos` entry per `ids` entry.
    super::polls::attach_polls(state, viewer, &ids, &mut dtos).await?;
    Ok(dtos)
}
