// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Who a message mentions, for anything that needs the answer outside of
//! push - today, the unread-mention badge `store::message_mentions`
//! persists.
//!
//! [`push::recipients::resolved_mentions`] already turns `@name`, `@[Role]`,
//! `@everyone` and `@here` into a set of account ids, gated the same way a
//! push wake already is (`MENTION_EVERYONE`, a role's `mentionable` flag).
//! That function's own candidate pool is push-registered accounts, the right
//! scope for "who to wake" but the wrong one for "who this message mentions
//! at all": an account with no device registered can still be mentioned.
//! [`mentioned_viewers`] calls the identical resolver against every live
//! account instead, so the two callers only ever disagree on scope, never on
//! what counts as a mention.

use crate::ids::{ChannelId, UserId};
use crate::presence::PresenceTracker;
use crate::push::recipients::resolved_mentions;
use crate::store::Store;

/// The accounts `content` (written by `author_id` in `channel_id`) mentions,
/// narrowed to whoever can actually view the channel - an account that
/// cannot see a channel can never see its rail entry either, so a mention
/// naming one is resolved away rather than stored as a mention nobody will
/// ever read as unread. The author is excluded from the candidate pool: a
/// message cannot leave its own sender an unread mention of themselves.
pub async fn mentioned_viewers(
    store: &Store,
    channel_id: ChannelId,
    author_id: UserId,
    content: &str,
    presence: &PresenceTracker,
) -> anyhow::Result<Vec<UserId>> {
    let mut candidates = store.all_live_user_ids().await?;
    candidates.retain(|id| *id != author_id);
    let viewers = store.viewers_among(channel_id, &candidates).await?;
    let mentioned =
        resolved_mentions(store, channel_id, author_id, content, &viewers, presence).await?;
    Ok(mentioned.into_iter().collect())
}
