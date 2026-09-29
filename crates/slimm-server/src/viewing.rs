// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Which channels a user's live connections report as open and in front of
//! them right now, so push can skip a message somebody is already reading.
//!
//! In-memory and per connection, like [`crate::presence::PresenceTracker`]:
//! a report lapses on its own after [`VIEWING_TTL`], so a client that is
//! suspended without closing its socket cannot silence push forever. It is
//! only ever read by the push path for the reporting user's own account and
//! is never broadcast, so a hidden presence stays hidden.

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};

use crate::ids::{ChannelId, UserId};

/// How long one report counts. Clients refresh well inside this.
pub const VIEWING_TTL: Duration = Duration::from_secs(90);

/// The most channels one connection may report at once; a thread and its
/// parent are the realistic ceiling, the rest is abuse.
pub const MAX_VIEWED_CHANNELS: usize = 8;

struct Report {
    channels: HashSet<ChannelId>,
    at: Instant,
}

#[derive(Clone, Default)]
pub struct ViewingTracker {
    reports: Arc<Mutex<HashMap<(UserId, u64), Report>>>,
    next_connection: Arc<AtomicU64>,
}

impl ViewingTracker {
    /// A fresh id for one live connection, to key its reports by.
    pub fn new_connection(&self) -> u64 {
        self.next_connection.fetch_add(1, Ordering::Relaxed)
    }

    /// Replaces what `connection` reports as open; an empty set clears it.
    pub fn set(&self, user_id: UserId, connection: u64, channels: HashSet<ChannelId>) {
        self.set_at(user_id, connection, channels, Instant::now());
    }

    pub fn set_at(
        &self,
        user_id: UserId,
        connection: u64,
        channels: HashSet<ChannelId>,
        now: Instant,
    ) {
        let mut reports = lock(&self.reports);
        if channels.is_empty() {
            reports.remove(&(user_id, connection));
            return;
        }
        reports.retain(|_, report| now.duration_since(report.at) < VIEWING_TTL);
        reports.insert((user_id, connection), Report { channels, at: now });
    }

    /// Forgets a connection, on every exit path of its socket.
    pub fn clear(&self, user_id: UserId, connection: u64) {
        lock(&self.reports).remove(&(user_id, connection));
    }

    /// Whether any live connection of `user_id` reported `channel_id` open
    /// within [`VIEWING_TTL`].
    pub fn is_viewing(&self, user_id: UserId, channel_id: ChannelId) -> bool {
        self.is_viewing_at(user_id, channel_id, Instant::now())
    }

    pub fn is_viewing_at(&self, user_id: UserId, channel_id: ChannelId, now: Instant) -> bool {
        lock(&self.reports).iter().any(|((user, _), report)| {
            *user == user_id
                && report.channels.contains(&channel_id)
                && now.duration_since(report.at) < VIEWING_TTL
        })
    }
}

/// A poisoned lock means another thread panicked mid-update; recover rather
/// than wedge the push path, the choice `presence` makes too.
fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn one(channel: ChannelId) -> HashSet<ChannelId> {
        HashSet::from([channel])
    }

    #[test]
    fn a_report_lapses_after_the_ttl() {
        let tracker = ViewingTracker::default();
        let (user, channel) = (UserId::generate(), ChannelId::generate());
        let start = Instant::now();
        tracker.set_at(user, 1, one(channel), start);
        assert!(tracker.is_viewing_at(user, channel, start + VIEWING_TTL - Duration::from_secs(1)));
        assert!(!tracker.is_viewing_at(user, channel, start + VIEWING_TTL));
    }

    #[test]
    fn clearing_one_connection_keeps_another() {
        let tracker = ViewingTracker::default();
        let (user, channel) = (UserId::generate(), ChannelId::generate());
        tracker.set(user, 1, one(channel));
        tracker.set(user, 2, one(channel));
        tracker.clear(user, 1);
        assert!(tracker.is_viewing(user, channel));
        tracker.set(user, 2, HashSet::new());
        assert!(!tracker.is_viewing(user, channel));
    }

    #[test]
    fn another_user_is_never_reported_as_viewing() {
        let tracker = ViewingTracker::default();
        let channel = ChannelId::generate();
        tracker.set(UserId::generate(), 1, one(channel));
        assert!(!tracker.is_viewing(UserId::generate(), channel));
    }
}
