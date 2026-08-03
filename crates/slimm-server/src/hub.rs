// SPDX-License-Identifier: AGPL-3.0-only
//! The in-process fan-out hub.
//!
//! Durable writes happen over REST; this hub carries the resulting events to
//! every connected WebSocket. It is a single broadcast channel: publishers (the
//! REST handlers) send an [`Event`], and each connection subscribes and filters
//! events down to what its user is allowed to see. That is ample for the small
//! self-hosted deployments this targets, and a per-scope router can replace it
//! later without changing the publish side.
//!
//! Delivery order across concurrent writers is best-effort: two racing sends to
//! the same channel may fan out in either order. Clients apply events strictly
//! by their per-scope `seq`, so a brief out-of-order arrival is reconciled on
//! the client and never surfaces as reordering.
//!
//! A subscriber that falls too far behind is dropped by the channel (a `Lagged`
//! receive); the connection treats that as backpressure and closes, and the
//! client resyncs over REST. Nothing here blocks a publisher.
//!
//! The hub also hands out connection slots, capping how many WebSockets can be
//! open at once so a connection flood cannot exhaust the process.

use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use tokio::sync::{OwnedSemaphorePermit, Semaphore, broadcast};

use crate::presence::PresenceTracker;
use crate::typing::TypingTracker;

mod event;
pub use event::Event;

/// How many events the channel buffers per subscriber before the slowest one
/// starts losing the oldest and receives a `Lagged` error. Referenced from
/// [`Event`]'s own doc comments, in `hub/event.rs`, as the bound a canvas
/// frame is sized against.
pub(crate) const CHANNEL_CAPACITY: usize = 1024;

/// Ceiling on simultaneously open WebSocket connections.
const MAX_CONNECTIONS: usize = 1024;

/// A cloneable handle to the broadcast channel and the connection limiter,
/// shared through app state.
///
/// Presence and typing are ephemeral, in-memory-only state (see
/// `crate::presence` and `crate::typing`), and both need to be visible to
/// every connection the way the broadcast channel already is, so they live
/// here rather than as their own `AppState` fields.
#[derive(Clone)]
pub struct Hub {
    sender: broadcast::Sender<Event>,
    slots: Arc<Semaphore>,
    presence: PresenceTracker,
    typing: TypingTracker,
    permissions_epoch: Arc<AtomicU64>,
    idle_poll_interval: Duration,
}

/// Default value of [`Hub::idle_poll_interval`]: how often a live connection
/// checks whether its user just crossed the idle threshold, in either
/// direction, so the transition can be announced (see
/// `http::ws::signals::watch_idle`). Idle itself does not move this fast; it
/// only bounds how long an announcement can lag the real transition by.
const IDLE_POLL_INTERVAL: Duration = Duration::from_secs(30);

/// Whether this event means somebody's permissions may have moved.
///
/// Exhaustive on purpose: a new variant does not compile until somebody
/// decides, and the safe answer for anything permission-shaped is `true`.
/// Over-reporting only costs a re-derivation; under-reporting is a stale
/// answer served to a caller who should no longer have it.
fn moves_permissions(event: &Event) -> bool {
    match event {
        Event::RoleChanged { .. }
        | Event::MemberRoleChanged { .. }
        | Event::MemberTimeoutChanged { .. }
        | Event::MemberRemoved(_)
        | Event::OverwriteChanged { .. }
        | Event::ChannelCreated(_)
        | Event::ChannelUpdated(_)
        | Event::ChannelDeleted { .. } => true,
        Event::MessageCreated { .. }
        | Event::MessageEdited { .. }
        | Event::MessageDeleted { .. }
        | Event::ReactionsChanged { .. }
        | Event::ThreadUpdated { .. }
        | Event::MessagePinned { .. }
        | Event::MessageUnpinned { .. }
        | Event::PollVoted { .. }
        | Event::TypingStarted { .. }
        | Event::TypingStopped { .. }
        | Event::PresenceChanged(_)
        | Event::ProfileChanged(_)
        | Event::CanvasObjectPlaced { .. }
        | Event::CanvasObjectsRemoved { .. }
        | Event::CanvasCleared { .. }
        | Event::CanvasObjectsRestored { .. }
        | Event::SessionRevoked(_)
        // A category grants and denies nothing (docs/decisions/0006).
        | Event::CategoryChanged => false,
    }
}

impl Default for Hub {
    fn default() -> Self {
        Self::new()
    }
}

impl Hub {
    pub fn new() -> Self {
        let (sender, _receiver) = broadcast::channel(CHANNEL_CAPACITY);
        Self {
            sender,
            slots: Arc::new(Semaphore::new(MAX_CONNECTIONS)),
            presence: PresenceTracker::new(),
            typing: TypingTracker::new(),
            permissions_epoch: Arc::new(AtomicU64::new(0)),
            idle_poll_interval: IDLE_POLL_INTERVAL,
        }
    }

    /// Builds a hub with a non-default typing TTL, so a test can wait out the
    /// self-expiry in milliseconds instead of the production few seconds.
    ///
    /// Delegates rather than repeating the body, the way `TypingTracker`'s own
    /// pair already does: a field added to one and not the other is the whole
    /// failure mode of a duplicated constructor, and this hub has grown a
    /// field since the copy was made.
    pub fn with_typing_ttl(ttl: Duration) -> Self {
        Self {
            typing: TypingTracker::with_ttl(ttl),
            ..Self::new()
        }
    }

    /// Builds a hub with a non-default idle poll interval, so a test can
    /// observe an idle transition being announced in milliseconds instead of
    /// the production 30 seconds, without needing 10 real minutes to pass to
    /// reach the idle threshold itself (see `presence::PresenceTracker`'s own
    /// `_at` methods for how a test drives that half instead).
    pub fn with_idle_poll_interval(interval: Duration) -> Self {
        Self {
            idle_poll_interval: interval,
            ..Self::new()
        }
    }

    /// How often a live connection checks whether its user just crossed the
    /// idle threshold; see [`Self::with_idle_poll_interval`].
    pub fn idle_poll_interval(&self) -> Duration {
        self.idle_poll_interval
    }

    /// Publishes an event to every current subscriber. Does nothing if there are
    /// none; never blocks or errors from the caller's point of view.
    pub fn publish(&self, event: Event) {
        // Bumped before the send, so no subscriber can act on a stale answer.
        if moves_permissions(&event) {
            self.permissions_epoch.fetch_add(1, Ordering::Release);
        }
        let _ = self.sender.send(event);
    }

    /// A counter bumped whenever a published event means permissions moved.
    ///
    /// This exists so a cached permission answer can be invalidated by the
    /// *write*, not by the reader's place in the event stream. Delivery order
    /// across concurrent writers is best-effort (see this module's own note),
    /// so a connection can receive a `message.created` published by one
    /// request before the `overwrite.changed` published by another that
    /// already committed. A cache keyed on events alone would serve the
    /// pre-revocation answer for that message. Bumping a shared counter inside
    /// `publish`, before the send, makes the invalidation immediate and global
    /// instead, and leaves only the gap between a handler's commit and its
    /// publish call - which carries no await in any handler that publishes one
    /// of these.
    pub fn permissions_epoch(&self) -> u64 {
        self.permissions_epoch.load(Ordering::Acquire)
    }

    /// Subscribes a new connection to the event stream.
    pub fn subscribe(&self) -> broadcast::Receiver<Event> {
        self.sender.subscribe()
    }

    /// Claims a connection slot, or `None` if the ceiling is reached. The permit
    /// is held for the connection's lifetime and releases the slot when dropped.
    pub fn try_connect(&self) -> Option<OwnedSemaphorePermit> {
        self.slots.clone().try_acquire_owned().ok()
    }

    /// The shared, cloneable presence tracker (a cheap `Arc` clone).
    pub fn presence(&self) -> PresenceTracker {
        self.presence.clone()
    }

    /// The shared, cloneable typing tracker (a cheap `Arc` clone).
    pub fn typing(&self) -> TypingTracker {
        self.typing.clone()
    }
}

#[cfg(test)]
mod epoch_tests {
    use super::*;
    use crate::ids::{ChannelId, RoleId, UserId};

    /// The property the view cache rests on: the counter moves inside
    /// `publish`, so it has already moved by the time anybody could receive
    /// the event - and for a subscriber that never receives it at all.
    ///
    /// That is the whole difference from invalidating as events arrive. A
    /// connection lagging behind its queue would otherwise keep serving a
    /// pre-revocation answer for every event still ahead of the revocation in
    /// its own backlog, however long ago the write committed.
    #[test]
    fn the_epoch_moves_before_any_subscriber_receives() {
        let hub = Hub::new();
        let mut rx = hub.subscribe();
        let before = hub.permissions_epoch();

        hub.publish(Event::OverwriteChanged {
            channel_id: ChannelId::generate(),
            previously_visible_to: Vec::new(),
        });

        assert!(
            hub.permissions_epoch() > before,
            "the epoch must move without anybody having read the event yet",
        );
        assert!(rx.try_recv().is_ok(), "and the event is still delivered");
    }

    /// A clone is what every handler holds, so an epoch that did not travel
    /// with it would move for nobody.
    #[test]
    fn a_clone_shares_the_same_counter() {
        let hub = Hub::new();
        let handle = hub.clone();
        let before = hub.permissions_epoch();
        handle.publish(Event::MemberRemoved(UserId::generate()));
        assert!(hub.permissions_epoch() > before);
    }

    /// Ordinary traffic must not move it, or the cache never holds anything
    /// and the whole change is a no-op with extra steps.
    #[test]
    fn channel_traffic_leaves_it_alone() {
        let hub = Hub::new();
        let before = hub.permissions_epoch();
        hub.publish(Event::TypingStarted {
            channel_id: ChannelId::generate(),
            user_id: UserId::generate(),
        });
        hub.publish(Event::PresenceChanged(UserId::generate()));
        hub.publish(Event::MessageDeleted {
            op_seq: None,
            channel_id: ChannelId::generate(),
            message_id: crate::ids::MessageId::generate(),
        });
        assert_eq!(hub.permissions_epoch(), before);
    }

    #[test]
    fn every_permission_shaped_event_moves_it() {
        let hub = Hub::new();
        for event in [
            Event::RoleChanged {
                role_id: RoleId::generate(),
            },
            Event::MemberRoleChanged {
                user_id: UserId::generate(),
                role_id: RoleId::generate(),
            },
            Event::MemberTimeoutChanged {
                user_id: UserId::generate(),
                until: Some(1),
            },
            Event::MemberRemoved(UserId::generate()),
            Event::ChannelDeleted {
                channel_id: ChannelId::generate(),
            },
        ] {
            let before = hub.permissions_epoch();
            hub.publish(event);
            assert!(hub.permissions_epoch() > before);
        }
    }
}
