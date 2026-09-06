// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Per-channel slow mode: the range check `channels::update` applies to an
//! incoming `slow_mode_seconds`, and the check `messages::send` applies to a
//! fresh send. No route of its own - slow mode is set through the existing
//! `PATCH /channels/{channel_id}` and enforced inline in `POST
//! /channels/{channel_id}/messages`.

use super::AppState;
use super::error::ApiError;
use crate::ids::{ChannelId, UserId};
use crate::permissions::Permissions;
use crate::store::now_ms;

/// The highest interval a channel may be set to: six hours. A policy choice,
/// not a hard invariant, so it lives here rather than as a `CHECK` in the
/// migration - the same split `screen_share_max_height` and
/// `canvas_object_cap` use.
pub(crate) const SLOW_MODE_MAX_SECONDS: i64 = 6 * 60 * 60;

/// Bounds a `slow_mode_seconds` update. Refused outright rather than
/// clamped: a caller asking for a week's interval almost certainly mistyped
/// units, and silently capping it would leave them believing they set what
/// they asked for.
pub(crate) fn validate_slow_mode_seconds(seconds: i64) -> Result<i64, ApiError> {
    if !(0..=SLOW_MODE_MAX_SECONDS).contains(&seconds) {
        return Err(ApiError::BadRequest(
            "slow_mode_seconds must be between 0 and 21600",
        ));
    }
    Ok(seconds)
}

/// Refuses a fresh send that arrives before the channel's slow-mode interval
/// has elapsed since `author_id`'s own last live message here. A no-op when
/// slow mode is off, or when `author_id` holds `MANAGE_CHANNELS` in this
/// channel - the one lever between "nothing" and a full timeout, so its
/// holder is exempt from the lesser one too.
///
/// Never called for an idempotent retry of an already-stored send; see
/// `messages::send`'s own `stored_already` guard, which decides that before
/// reaching here.
pub(crate) async fn enforce_slow_mode(
    state: &AppState,
    channel_id: ChannelId,
    author_id: UserId,
) -> Result<(), ApiError> {
    let seconds = state.store.channel_slow_mode_seconds(channel_id).await?;
    if seconds <= 0 {
        return Ok(());
    }
    if state
        .store
        .has_permission(author_id, channel_id, Permissions::MANAGE_CHANNELS)
        .await?
    {
        return Ok(());
    }
    let Some(last_sent_at) = state.store.last_message_at(channel_id, author_id).await? else {
        return Ok(());
    };
    let window_ms = seconds * 1000;
    let elapsed_ms = now_ms() - last_sent_at;
    if elapsed_ms >= window_ms {
        return Ok(());
    }
    let remaining_ms = window_ms - elapsed_ms;
    // Rounds up so a client that waits the reported number of seconds is never refused a second time.
    let retry_after_seconds = ((remaining_ms + 999) / 1000).max(1);
    Err(ApiError::SlowMode {
        retry_after_seconds,
    })
}
