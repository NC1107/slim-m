// SPDX-License-Identifier: AGPL-3.0-only
//! Collapsing a burst of messages into one wake per recipient.
//!
//! Split out of [`super`] because it is a self-contained decision with its own
//! invariant - a window may only stay shut when somebody was really woken -
//! and because that invariant is worth testing without a store, a relay, or an
//! HTTP stack anywhere near it. [`super::deliver`] is the only caller.

use std::collections::HashMap;
use std::sync::Mutex;

use crate::ids::{ChannelId, UserId};
use crate::store::now_ms;

/// Collapses a burst of triggers into one per `(channel, recipient)`.
/// Leading-edge: the first trigger after a window last elapsed, or was
/// released (see [`Self::release_if_undelivered`]), opens the window and
/// records `now`; every other trigger for that same pair inside the window is
/// suppressed.
///
/// Keyed on the pair, not the channel alone: one recipient's suppressed
/// window must never silence a different recipient's wake. Debouncing exists
/// to collapse a burst of messages for one person, not to let one recipient's
/// state (or bad luck) silence somebody else's notification.
pub(super) struct Debounce {
    window_ms: i64,
    last_fired: Mutex<HashMap<(ChannelId, UserId), i64>>,
}

impl Debounce {
    pub(super) fn new(window_ms: i64) -> Self {
        Self {
            window_ms,
            last_fired: Mutex::new(HashMap::new()),
        }
    }

    /// Attempts to open a window for `(channel_id, user_id)`. `Some(fired_at)`
    /// means this trigger is not suppressed and the caller now owns the
    /// window: if it turns out nobody was actually notified, it must call
    /// [`Self::release_if_undelivered`] with the same `fired_at`, or the next
    /// genuine trigger for this recipient would be wrongly suppressed too.
    /// `None` means a burst is already collapsed into an open window.
    pub(super) fn try_fire(&self, channel_id: ChannelId, user_id: UserId) -> Option<i64> {
        self.try_fire_at(channel_id, user_id, now_ms())
    }

    /// [`Self::try_fire`] with an explicit clock, for deterministic tests.
    pub(super) fn try_fire_at(
        &self,
        channel_id: ChannelId,
        user_id: UserId,
        now: i64,
    ) -> Option<i64> {
        let mut last_fired = self.lock();
        let key = (channel_id, user_id);
        match last_fired.get(&key) {
            Some(&last) if now - last < self.window_ms => None,
            _ => {
                last_fired.insert(key, now);
                Some(now)
            }
        }
    }

    /// Releases a window that turned out to deliver nobody anything, so the
    /// next trigger for this recipient is not suppressed by a burst whose
    /// leading edge failed. A no-op if the window has already moved on (it
    /// elapsed naturally and was re-opened by a later, successful trigger)
    /// since `fired_at`, so a late release from a slow delivery task can never
    /// claw back a newer window.
    pub(super) fn release_if_undelivered(
        &self,
        channel_id: ChannelId,
        user_id: UserId,
        fired_at: i64,
    ) {
        let mut last_fired = self.lock();
        let key = (channel_id, user_id);
        if last_fired.get(&key) == Some(&fired_at) {
            last_fired.remove(&key);
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<(ChannelId, UserId), i64>> {
        match self.last_fired.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn user() -> UserId {
        UserId::generate()
    }

    #[test]
    fn debounce_collapses_a_burst_then_reopens() {
        let debounce = Debounce::new(1_000);
        let channel = ChannelId::generate();
        let bob = user();
        assert!(
            debounce.try_fire_at(channel, bob, 0).is_some(),
            "first trigger fires"
        );
        assert!(
            debounce.try_fire_at(channel, bob, 500).is_none(),
            "inside the window is suppressed"
        );
        assert!(
            debounce.try_fire_at(channel, bob, 999).is_none(),
            "still inside the window"
        );
        assert!(
            debounce.try_fire_at(channel, bob, 1_000).is_some(),
            "the window has fully elapsed"
        );
    }

    #[test]
    fn debounce_is_independent_per_channel() {
        let debounce = Debounce::new(1_000);
        let a = ChannelId::generate();
        let b = ChannelId::generate();
        let bob = user();
        assert!(debounce.try_fire_at(a, bob, 0).is_some());
        // A burst in channel a does not suppress channel b.
        assert!(debounce.try_fire_at(b, bob, 0).is_some());
        assert!(debounce.try_fire_at(a, bob, 100).is_none());
    }

    /// Regression: the debounce used to be keyed on channel alone, so a window
    /// opened by one recipient's message silenced every other recipient in the
    /// same channel for the rest of that window.
    #[test]
    fn debounce_is_independent_per_recipient() {
        let debounce = Debounce::new(1_000);
        let channel = ChannelId::generate();
        let bob = user();
        let carol = user();
        assert!(debounce.try_fire_at(channel, bob, 0).is_some());
        assert!(
            debounce.try_fire_at(channel, carol, 50).is_some(),
            "bob's open window must not suppress carol's wake"
        );
        assert!(
            debounce.try_fire_at(channel, bob, 100).is_none(),
            "bob's own burst is still collapsed"
        );
    }

    /// Regression: a leading trigger that ends up delivering nobody anything
    /// (a relay error, or every device filtered out) used to spend the window
    /// regardless, dropping the next message's wake outright instead of merely
    /// collapsing it.
    #[test]
    fn release_if_undelivered_reopens_the_window_immediately() {
        let debounce = Debounce::new(1_000);
        let channel = ChannelId::generate();
        let bob = user();
        let fired_at = debounce
            .try_fire_at(channel, bob, 0)
            .expect("first trigger fires");
        debounce.release_if_undelivered(channel, bob, fired_at);
        assert!(
            debounce.try_fire_at(channel, bob, 1).is_some(),
            "a window that delivered nothing must not suppress the very next trigger"
        );
    }

    #[test]
    fn release_if_undelivered_does_not_clobber_a_newer_window() {
        let debounce = Debounce::new(1_000);
        let channel = ChannelId::generate();
        let bob = user();
        let stale_fired_at = debounce.try_fire_at(channel, bob, 0).unwrap();
        // The window elapses naturally and opens again for a later message.
        assert!(debounce.try_fire_at(channel, bob, 1_000).is_some());
        // A late release from the first task must not tear the second down.
        debounce.release_if_undelivered(channel, bob, stale_fired_at);
        assert!(
            debounce.try_fire_at(channel, bob, 1_500).is_none(),
            "the newer window must still be in effect"
        );
    }
}
