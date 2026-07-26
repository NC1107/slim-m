// SPDX-License-Identifier: AGPL-3.0-only
//! Ephemeral, in-memory presence: who currently has a live WebSocket, and the
//! one pure rule for what status a given viewer may be told about a given
//! user.
//!
//! Presence is derived from live connections, never self-reported, so a
//! client that crashes cannot stay "online" forever: the only way into
//! [`PresenceTracker`] is a connection actually opening, and the only way out
//! is that connection closing, which `http::ws::serve` guarantees runs on
//! every exit path with a drop guard. Nothing here is written to SQLite: a
//! row per heartbeat would be pure write amplification on an embedded
//! database for a value that is stale the instant it is read back after a
//! crash.
//!
//! The one thing that IS a durable user choice is [`Visibility`]: whether to
//! show up as online, away, or dnd, or to appear offline to everyone else
//! (`Hidden`). That preference lives in SQLite (`users.presence_visibility`,
//! migration 0008); [`crate::store::Store::presence_visibility`] reads it.
//!
//! [`status_for`] is the single place that decides what a viewer sees, and it
//! is deliberately the only place: every surface that exposes presence (the
//! REST batch lookup in `http::presence` and the WebSocket broadcast in
//! `http::ws`) calls this same function with the same inputs, so a hidden
//! user's real status has exactly one choke point to leak through rather than
//! one per surface.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};

use crate::ids::UserId;

/// How long a connected user with no observed activity (a ping, a typing
/// refresh, anything inbound) is shown as away rather than online, absent an
/// explicit away/dnd/hidden preference. Only affects the `Online` preference;
/// a user who chose Away, Dnd, or Hidden already said what they want shown.
pub const IDLE_TIMEOUT: Duration = Duration::from_secs(10 * 60);

/// The status a user has durably chosen, independent of whether they are
/// connected right now. Persisted in `users.presence_visibility`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Visibility {
    #[default]
    Online,
    Away,
    Dnd,
    /// Appear offline to everyone else. The owner's decision record calls
    /// this presence's "hide/appear-offline option"; the user's own client
    /// still sees their true connection-derived state (see [`status_for`]).
    Hidden,
}

impl Visibility {
    pub const fn as_str(self) -> &'static str {
        match self {
            Visibility::Online => "online",
            Visibility::Away => "away",
            Visibility::Dnd => "dnd",
            Visibility::Hidden => "hidden",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "online" => Visibility::Online,
            "away" => Visibility::Away,
            "dnd" => Visibility::Dnd,
            "hidden" => Visibility::Hidden,
            _ => return None,
        })
    }
}

/// What a viewer is told a user's status is. Never `Hidden` on the wire: that
/// preference either renders as `Offline` (any other viewer) or resolves to
/// the real connection-derived status (the user viewing themselves); see
/// [`status_for`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Online,
    Away,
    Dnd,
    Offline,
}

impl Status {
    pub const fn as_str(self) -> &'static str {
        match self {
            Status::Online => "online",
            Status::Away => "away",
            Status::Dnd => "dnd",
            Status::Offline => "offline",
        }
    }
}

/// Resolves what `viewer` may be told about `target`'s presence.
///
/// `connected` and `idle` describe `target`'s live sockets, derived from
/// [`PresenceTracker`], never from anything a client asserts about itself.
/// The one asymmetry is deliberate: a target who chose [`Visibility::Hidden`]
/// is always `Offline` to anyone else, but sees their own true state, because
/// appear-offline is a decision to hide from other people, not from your own
/// client.
pub fn status_for(
    viewer: UserId,
    target: UserId,
    visibility: Visibility,
    connected: bool,
    idle: bool,
) -> Status {
    if !connected {
        return Status::Offline;
    }
    match visibility {
        Visibility::Hidden if viewer != target => Status::Offline,
        Visibility::Hidden => Status::Online,
        Visibility::Dnd => Status::Dnd,
        Visibility::Away => Status::Away,
        Visibility::Online if idle => Status::Away,
        Visibility::Online => Status::Online,
    }
}

/// Tracks, per user, how many live WebSocket connections are open and when
/// one last showed activity. Nothing here is itself a status: these are only
/// the connection facts [`status_for`] combines with a [`Visibility`] to
/// answer what a viewer sees.
#[derive(Clone)]
pub struct PresenceTracker {
    state: Arc<Mutex<HashMap<UserId, Entry>>>,
}

struct Entry {
    connections: u32,
    last_active: Instant,
}

impl Default for PresenceTracker {
    fn default() -> Self {
        Self::new()
    }
}

impl PresenceTracker {
    pub fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Records a new live connection. Returns `true` if this is the user's
    /// first (a transition worth publishing); a second device connecting
    /// while the first is still live is not a change anyone needs telling
    /// about.
    pub fn connect(&self, user_id: UserId) -> bool {
        self.connect_at(user_id, Instant::now())
    }

    /// [`Self::connect`] with an explicit clock, so a test can drive idle
    /// timing deterministically instead of sleeping.
    pub fn connect_at(&self, user_id: UserId, now: Instant) -> bool {
        let mut state = lock(&self.state);
        let entry = state.entry(user_id).or_insert(Entry {
            connections: 0,
            last_active: now,
        });
        entry.connections += 1;
        entry.last_active = now;
        entry.connections == 1
    }

    /// Records a connection closing. Returns `true` if that was the user's
    /// last live connection.
    pub fn disconnect(&self, user_id: UserId) -> bool {
        self.disconnect_at(user_id, Instant::now())
    }

    /// [`Self::disconnect`] with an explicit clock.
    pub fn disconnect_at(&self, user_id: UserId, now: Instant) -> bool {
        let mut state = lock(&self.state);
        let Some(entry) = state.get_mut(&user_id) else {
            return false;
        };
        entry.connections = entry.connections.saturating_sub(1);
        entry.last_active = now;
        if entry.connections == 0 {
            state.remove(&user_id);
            true
        } else {
            false
        }
    }

    /// Marks a connected user as recently active, resetting the idle clock.
    pub fn touch(&self, user_id: UserId) {
        self.touch_at(user_id, Instant::now());
    }

    /// [`Self::touch`] with an explicit clock.
    pub fn touch_at(&self, user_id: UserId, now: Instant) {
        if let Some(entry) = lock(&self.state).get_mut(&user_id) {
            entry.last_active = now;
        }
    }

    pub fn is_connected(&self, user_id: UserId) -> bool {
        lock(&self.state).contains_key(&user_id)
    }

    pub fn is_idle(&self, user_id: UserId) -> bool {
        self.is_idle_at(user_id, Instant::now())
    }

    /// [`Self::is_idle`] with an explicit clock.
    pub fn is_idle_at(&self, user_id: UserId, now: Instant) -> bool {
        lock(&self.state)
            .get(&user_id)
            .map(|entry| now.duration_since(entry.last_active) >= IDLE_TIMEOUT)
            .unwrap_or(false)
    }
}

/// A poisoned lock means another thread panicked mid-update; recover rather
/// than wedging every presence read behind a dead tracker, the same choice
/// [`crate::ratelimit::RateLimiter`] makes.
fn lock(state: &Mutex<HashMap<UserId, Entry>>) -> MutexGuard<'_, HashMap<UserId, Entry>> {
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

    #[test]
    fn hidden_reads_as_offline_to_others_but_true_to_self() {
        let alice = uid();
        let bob = uid();
        let status = status_for(bob, alice, Visibility::Hidden, true, false);
        assert_eq!(
            status,
            Status::Offline,
            "others see a hidden user as offline"
        );

        let self_status = status_for(alice, alice, Visibility::Hidden, true, false);
        assert_eq!(
            self_status,
            Status::Online,
            "the hidden user's own client sees their true state"
        );
    }

    #[test]
    fn disconnected_is_always_offline_regardless_of_visibility() {
        let alice = uid();
        for visibility in [
            Visibility::Online,
            Visibility::Away,
            Visibility::Dnd,
            Visibility::Hidden,
        ] {
            assert_eq!(
                status_for(alice, alice, visibility, false, false),
                Status::Offline
            );
        }
    }

    #[test]
    fn online_goes_away_when_idle() {
        let alice = uid();
        assert_eq!(
            status_for(alice, alice, Visibility::Online, true, false),
            Status::Online
        );
        assert_eq!(
            status_for(alice, alice, Visibility::Online, true, true),
            Status::Away
        );
    }

    #[test]
    fn away_and_dnd_pass_through_while_connected() {
        let alice = uid();
        assert_eq!(
            status_for(alice, alice, Visibility::Away, true, false),
            Status::Away
        );
        assert_eq!(
            status_for(alice, alice, Visibility::Dnd, true, false),
            Status::Dnd
        );
    }

    #[test]
    fn first_connect_and_last_disconnect_are_the_only_transitions() {
        let tracker = PresenceTracker::new();
        let alice = uid();

        assert!(tracker.connect(alice), "first connection is a transition");
        assert!(
            !tracker.connect(alice),
            "a second device is not a fresh transition"
        );
        assert!(tracker.is_connected(alice));

        assert!(
            !tracker.disconnect(alice),
            "one of two connections closing is not the last"
        );
        assert!(tracker.is_connected(alice), "still connected on the second");
        assert!(
            tracker.disconnect(alice),
            "the last connection closing is a transition"
        );
        assert!(!tracker.is_connected(alice));
    }

    #[test]
    fn disconnect_without_a_matching_connect_is_a_no_op() {
        let tracker = PresenceTracker::new();
        assert!(!tracker.disconnect(uid()));
    }

    #[test]
    fn idle_is_measured_from_last_activity() {
        let tracker = PresenceTracker::new();
        let alice = uid();
        let start = Instant::now();
        tracker.connect_at(alice, start);
        assert!(!tracker.is_idle_at(alice, start));

        let past_timeout = start + IDLE_TIMEOUT + Duration::from_secs(1);
        assert!(tracker.is_idle_at(alice, past_timeout));

        // A touch resets the clock even past the old timeout.
        tracker.touch_at(alice, past_timeout);
        assert!(!tracker.is_idle_at(alice, past_timeout));
    }
}
