// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Moving an account's read marker and telling its other devices.

use super::AppState;
use super::error::ApiError;
use crate::hub::Event;
use crate::ids::{ChannelId, UserId};

/// Advances `user_id`'s marker in `channel_id` and fans the result out to that
/// account's own sessions, so a badge clears on every device and not only the
/// one that read. The frame carries the stored marker, which is monotonic and
/// clamped, not the requested `seq`.
pub(super) async fn advance_and_announce(
    state: &AppState,
    user_id: UserId,
    channel_id: ChannelId,
    seq: i64,
) -> Result<(), ApiError> {
    state.store.mark_read(user_id, channel_id, seq).await?;
    let last_read_seq = state.store.last_read_seq(user_id, channel_id).await?;
    state.hub.publish(Event::ReadStateChanged {
        user_id,
        channel_id,
        last_read_seq,
    });
    Ok(())
}

/// Your own message is never unread to you, on this device or any other.
///
/// Best-effort: the message already landed, a missed marker only leaves a
/// badge, and the next read fixes it, so a failure must not fail the send.
pub(super) async fn advance_for_author(
    state: &AppState,
    author_id: UserId,
    message: &crate::store::Message,
) {
    let advanced = advance_and_announce(state, author_id, message.channel_id, message.seq.0).await;
    if advanced.is_err() {
        tracing::warn!(channel_id = %message.channel_id, "failed to advance the author's read marker");
    }
}
