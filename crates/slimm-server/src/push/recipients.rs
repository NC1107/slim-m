// SPDX-License-Identifier: AGPL-3.0-only
//! Who gets woken for a message, and why each exclusion is there.
//!
//! Its own module rather than three steps inside [`super::deliver`]'s
//! fire-and-forget task: this is the whole authorization decision on the push
//! path, and a task that reports to nothing but the process log cannot be
//! tested. `tests/blocking_reach.rs` drives it directly.

use crate::ids::{ChannelId, UserId};
use crate::store::Store;

/// Who should be woken for a message in `channel_id` written by `author_id`.
///
/// The set is built from who could receive a push at all, then filtered by view
/// permission, rather than evaluating permissions for every live user and then
/// asking which of them have a device. Both orders give the same recipients, but
/// this one costs a single indexed query on a deployment where nobody has
/// registered for push, instead of a full permission evaluation per user on
/// every message sent. The view check itself is not an optimization to skip: a
/// recipient who cannot see the channel must never be told a message landed in
/// it.
///
/// The author is dropped, and so is anybody who has blocked them. Push is the
/// one surface a client-side block filter cannot reach - the notification is on
/// the device before any filter runs - and a phone that buzzes for a message the
/// app then hides is worse than no filtering, since it reports exactly when the
/// blocked person spoke. It stays a view choice rather than a moderation action:
/// the message is delivered to everybody else and the author is never told.
pub async fn message_recipients(
    store: &Store,
    channel_id: ChannelId,
    author_id: UserId,
) -> anyhow::Result<Vec<UserId>> {
    // Push registrations first, permissions second; see the note above.
    let candidates = store.users_with_push_devices().await?;
    let blockers = store.blockers_of(author_id).await?;
    let candidates: Vec<UserId> = candidates
        .into_iter()
        .filter(|user_id| *user_id != author_id && !blockers.contains(user_id))
        .collect();
    store.viewers_among(channel_id, &candidates).await
}
