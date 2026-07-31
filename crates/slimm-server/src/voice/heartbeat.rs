// SPDX-License-Identifier: AGPL-3.0-only
//! Bounds how long a terminated app can leave a ghost participant in a room.
//!
//! A LiveKit room reaps a dead connection on its own once ICE gives up on it,
//! but that is an SFU implementation default this project does not set and
//! should not lean on: it is what a device that is genuinely killed (no
//! socket close, no goodbye, nothing) leaves behind, and how long it takes is
//! whatever the SFU's own tuning happens to be. [`CallHeartbeats`] is the
//! owned, tested backstop: a client still on a call keeps refreshing its
//! entry (`POST .../voice/heartbeat`, on a plain interval, independent of
//! app-foreground state so a backgrounded call is never mistaken for a dead
//! one), and [`CallHeartbeats::sweep_stale`] hands back everyone whose
//! refresh has gone quiet for longer than a real client, even a briefly
//! reconnecting one, plausibly would.
//!
//! Deliberately in-memory, the same call [`crate::presence::PresenceTracker`]
//! makes: a row per heartbeat would be pure write amplification for a value
//! that means nothing the instant a process restarts anyway, since every
//! LiveKit connection it could describe would already be gone too.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};

use crate::ids::{ChannelId, UserId};

/// How long a heartbeat may go unrefreshed before [`CallHeartbeats::sweep_stale`]
/// gives it up. About 2.5x the client's own interval, so one dropped request
/// under a flaky connection does not evict somebody still genuinely on the
/// call; see `voice_controller.dart`'s `voiceHeartbeatInterval`.
pub const STALE_AFTER: Duration = Duration::from_secs(40);

/// Tracks the last heartbeat seen for each `(user, channel)` voice session.
#[derive(Clone, Default)]
pub struct CallHeartbeats {
    state: Arc<Mutex<HashMap<(UserId, ChannelId), Instant>>>,
}

impl CallHeartbeats {
    pub fn new() -> Self {
        Self::default()
    }

    /// Records a heartbeat now, creating the entry on its first one.
    pub fn record(&self, user_id: UserId, channel_id: ChannelId) {
        self.record_at(user_id, channel_id, Instant::now());
    }

    /// [`Self::record`] with an explicit clock, so a test can drive staleness
    /// deterministically instead of sleeping.
    pub fn record_at(&self, user_id: UserId, channel_id: ChannelId, now: Instant) {
        lock(&self.state).insert((user_id, channel_id), now);
    }

    /// Whether an entry exists at all, regardless of freshness. Production
    /// code only ever needs [`Self::sweep_stale`]; this is for a test to
    /// confirm a heartbeat was actually recorded.
    pub fn contains(&self, user_id: UserId, channel_id: ChannelId) -> bool {
        lock(&self.state).contains_key(&(user_id, channel_id))
    }

    /// Drops a tracked session outright, e.g. once it has already been
    /// evicted for some other reason (a kick, a ban): a later sweep then has
    /// nothing stale left to rediscover and call the SFU about again.
    pub fn forget(&self, user_id: UserId, channel_id: ChannelId) {
        lock(&self.state).remove(&(user_id, channel_id));
    }

    /// Removes and returns every session whose last heartbeat is at least
    /// `threshold` old as of now.
    pub fn sweep_stale(&self, threshold: Duration) -> Vec<(UserId, ChannelId)> {
        self.sweep_stale_at(threshold, Instant::now())
    }

    /// [`Self::sweep_stale`] with an explicit clock.
    pub fn sweep_stale_at(&self, threshold: Duration, now: Instant) -> Vec<(UserId, ChannelId)> {
        let mut state = lock(&self.state);
        let stale: Vec<_> = state
            .iter()
            .filter(|&(_, &last)| now.duration_since(last) >= threshold)
            .map(|(&key, _)| key)
            .collect();
        for key in &stale {
            state.remove(key);
        }
        stale
    }
}

/// A poisoned lock means another thread panicked mid-update; recover rather
/// than wedging every heartbeat behind a dead tracker, the choice
/// [`crate::presence::PresenceTracker`] and [`crate::ratelimit::RateLimiter`]
/// both already make.
fn lock(
    state: &Mutex<HashMap<(UserId, ChannelId), Instant>>,
) -> MutexGuard<'_, HashMap<(UserId, ChannelId), Instant>> {
    match state.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn uid() -> UserId {
        UserId::generate()
    }

    fn cid() -> ChannelId {
        ChannelId::generate()
    }

    #[test]
    fn a_fresh_heartbeat_is_not_stale() {
        let heartbeats = CallHeartbeats::new();
        let (user, channel) = (uid(), cid());
        let now = Instant::now();
        heartbeats.record_at(user, channel, now);

        assert!(heartbeats.sweep_stale_at(STALE_AFTER, now).is_empty());
    }

    #[test]
    fn a_heartbeat_that_stops_arriving_goes_stale() {
        let heartbeats = CallHeartbeats::new();
        let (user, channel) = (uid(), cid());
        let start = Instant::now();
        heartbeats.record_at(user, channel, start);

        let past = start + STALE_AFTER + Duration::from_secs(1);
        assert_eq!(
            heartbeats.sweep_stale_at(STALE_AFTER, past),
            [(user, channel)]
        );
    }

    #[test]
    fn a_refreshed_heartbeat_survives_past_the_old_deadline() {
        let heartbeats = CallHeartbeats::new();
        let (user, channel) = (uid(), cid());
        let start = Instant::now();
        heartbeats.record_at(user, channel, start);

        // A backgrounded-but-alive call: the refresh lands before the deadline.
        let refreshed_at = start + Duration::from_secs(5);
        heartbeats.record_at(user, channel, refreshed_at);

        let past_old_deadline = start + STALE_AFTER + Duration::from_secs(1);
        assert!(
            heartbeats
                .sweep_stale_at(STALE_AFTER, past_old_deadline)
                .is_empty(),
            "the refresh must count from its own timestamp, not the first one"
        );
    }

    #[test]
    fn a_swept_entry_is_removed_so_it_is_not_reported_twice() {
        let heartbeats = CallHeartbeats::new();
        let (user, channel) = (uid(), cid());
        let start = Instant::now();
        heartbeats.record_at(user, channel, start);

        let past = start + STALE_AFTER + Duration::from_secs(1);
        assert_eq!(heartbeats.sweep_stale_at(STALE_AFTER, past).len(), 1);
        assert!(heartbeats.sweep_stale_at(STALE_AFTER, past).is_empty());
    }

    #[test]
    fn forgetting_an_entry_stops_it_from_ever_going_stale() {
        let heartbeats = CallHeartbeats::new();
        let (user, channel) = (uid(), cid());
        let start = Instant::now();
        heartbeats.record_at(user, channel, start);
        heartbeats.forget(user, channel);

        let past = start + STALE_AFTER + Duration::from_secs(1);
        assert!(heartbeats.sweep_stale_at(STALE_AFTER, past).is_empty());
    }
}
