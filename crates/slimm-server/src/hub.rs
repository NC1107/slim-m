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

use crate::ids::{ChannelId, MessageId, RoleId, SessionId, UserId};
use crate::presence::PresenceTracker;
use crate::store::{AttachmentSummary, CanvasObject, Channel, Message};
use crate::typing::TypingTracker;

/// How many events the channel buffers per subscriber before the slowest one
/// starts losing the oldest and receives a `Lagged` error.
const CHANNEL_CAPACITY: usize = 1024;

/// Ceiling on simultaneously open WebSocket connections.
const MAX_CONNECTIONS: usize = 1024;

/// Something that happened and should reach interested connections.
#[derive(Debug, Clone)]
pub enum Event {
    /// A message was created; carries the full row so a connection can render
    /// the wire frame without another query.
    ///
    /// Attachments ride along because a brand new message can already have
    /// them and the row cannot express them. The sender reads them once for
    /// its own response, so this costs no extra query; leaving them out sent
    /// an image that only appeared on the next sync.
    MessageCreated {
        message: Message,
        attachments: Vec<AttachmentSummary>,
    },
    /// A message was edited.
    MessageEdited(Message),
    /// A poll's votes changed. Carries the whole per-option tally rather than
    /// a delta, so a client that missed a frame cannot drift, exactly like
    /// `ReactionsChanged`; who cast which vote is deliberately never present.
    PollVoted {
        channel_id: ChannelId,
        message_id: MessageId,
        options: Vec<(i64, i64)>,
    },
    /// A message was soft-deleted; carries only the ids a live connection
    /// needs to drop it from view, not the content it no longer shows.
    MessageDeleted {
        channel_id: ChannelId,
        message_id: MessageId,
    },
    /// A message's reactions changed. Carries the ids only: the tally itself is
    /// per viewer, since a reactor the receiver has blocked is not counted for
    /// them, so it is derived per receiving connection at send time the way
    /// [`Event::PresenceChanged`]'s status is. A precomputed tally here would be
    /// one global answer fanned out to everybody, which is exactly what made a
    /// live reaction undo a block.
    ReactionsChanged {
        channel_id: ChannelId,
        message_id: MessageId,
    },
    /// A message was pinned in a channel.
    MessagePinned {
        channel_id: ChannelId,
        message_id: MessageId,
        /// Null once the pinner's account is anonymized.
        pinned_by: Option<UserId>,
        pinned_at: i64,
    },
    /// A message was unpinned.
    MessageUnpinned {
        channel_id: ChannelId,
        message_id: MessageId,
    },
    /// A session was revoked; any live connection on it must close at once.
    SessionRevoked(SessionId),
    /// A user's live connection count transitioned to or from zero, or their
    /// visibility preference changed while connected. Carries only the user
    /// id: each connection derives its own per-viewer status at delivery time
    /// (see `http::ws::authorize`), so a hidden user's true state is never
    /// present in the event payload, only in the answer computed for one
    /// specific viewer.
    PresenceChanged(UserId),
    /// A member was timed out, or their timeout was lifted. `until` is Unix
    /// milliseconds, or `None` for a lift.
    ///
    /// Deployment-wide rather than channel-scoped, and carrying the deadline
    /// rather than only an id: unlike presence there is nothing per-viewer to
    /// derive, since the badge is the same fact for everyone who can see the
    /// member at all. Without this a timed-out member's composer stays
    /// enabled and their sends start failing with 403, which reads as the app
    /// being broken rather than as something a moderator did.
    MemberTimeoutChanged { user_id: UserId, until: Option<i64> },
    /// A member was removed from the Space. Their own sockets close on the
    /// `SessionRevoked` events that accompany this; everyone else's member
    /// list uses this to drop them without waiting for a refetch.
    MemberRemoved(UserId),
    /// Someone started or refreshed typing in a channel.
    TypingStarted {
        channel_id: ChannelId,
        user_id: UserId,
    },
    /// A typing state ended, either by lapsing on its own without a refresh
    /// or an explicit end; the two are indistinguishable on the wire. See
    /// `crate::typing`.
    TypingStopped {
        channel_id: ChannelId,
        user_id: UserId,
    },
    /// A role was created, renamed, had its permission bits changed, or was
    /// deleted. Carries only the id, never the name or the bits: those are
    /// gated behind MANAGE_ROLES over REST (`GET /roles`), and broadcasting
    /// either here would hand every member a privileged answer this event has
    /// no way to check them against. Deployment-wide like
    /// [`Event::MemberTimeoutChanged`] for the same reason: a role's bits feed
    /// every channel's evaluation at once, so there is no bounded per-channel
    /// audience to compute instead. A receiving client cannot resolve what
    /// changed, only that it should re-ask what it is now allowed to do.
    RoleChanged { role_id: RoleId },
    /// A role was granted to or revoked from a member. Carries both ids,
    /// which leaks nothing beyond `GET /members` already does for any caller:
    /// a member's held role ids are on their public profile. Broadcast rather
    /// than gated on the receiver for the same reason [`Event::MemberRemoved`]
    /// is: the fact itself is not privileged, only a role's bits are, and
    /// those never travel here either.
    MemberRoleChanged { user_id: UserId, role_id: RoleId },
    /// A channel was created. Carries the full row, the way
    /// [`Event::MessageCreated`] carries its message: a fresh channel has no
    /// prior state to reconcile against, so whoever can view it right now is
    /// exactly who should be told, the same channel-scoped check every
    /// message event already uses.
    ChannelCreated(Channel),
    /// A channel was renamed or had its topic replaced. Never changes what a
    /// channel's permission model allows, so the ordinary current-state
    /// channel-scoped check is exact here too: nobody's view of the channel
    /// changes, only its name or topic.
    ChannelUpdated(Channel),
    /// A channel was soft-deleted. Carries only the id: there is nothing left
    /// to show once it is gone. Gated specially in `http::ws::authorize`
    /// rather than through the ordinary channel-scoped check, which would
    /// always answer "no such channel" the instant this fires and so would
    /// never reach anyone - see
    /// [`crate::store::Store::viewed_channel_before_delete`].
    ChannelDeleted { channel_id: ChannelId },
    /// A channel permission overwrite was set or cleared for one role or one
    /// member. Carries only the channel id: the allow/deny mask is exactly
    /// the kind of privileged detail [`Event::RoleChanged`] withholds, and for
    /// the same reason. Gated by the ordinary current-state channel-scoped
    /// check, so a viewer who gains access is told immediately; a viewer
    /// whose access this exact change revokes is a known, accepted gap (see
    /// the audit finding this closes), since telling them precisely would need
    /// the same kind of pre-change snapshot [`Event::ChannelDeleted`] needed,
    /// scaled to however many members a role-targeted overwrite can name.
    OverwriteChanged {
        channel_id: ChannelId,
        /// Who could view the channel immediately *before* this overwrite was
        /// written, among the members it affects.
        ///
        /// Carried because the ordinary per-viewer check answers the question
        /// one instant too late: a connection whose view this very change
        /// revoked now fails it, so gating on the current answer alone delivers
        /// to everyone except the people the change was about - and their rail
        /// keeps showing a channel they can no longer open, which is the whole
        /// symptom this event exists to fix.
        ///
        /// It leaks nothing. Every id in it is somebody who could see the
        /// channel a moment ago, and the frame carries only the channel id.
        /// Bounded by the targeted role's membership, or by one for a member
        /// overwrite.
        previously_visible_to: Vec<UserId>,
    },
    /// An object was placed on a channel's canvas.
    ///
    /// Carries the whole row for the same reason [`Event::MessageCreated`]
    /// does: a brand new object has no prior state to reconcile against, and
    /// an id-only frame would cost every connected viewer one viewport read
    /// per stroke. It is bounded by the write route's props ceiling, which is
    /// sized against [`CHANNEL_CAPACITY`] rather than against any one drawing.
    ///
    /// Published only for a fresh write. An idempotent replay answers from the
    /// stored row and publishes nothing, so a retry cannot fan a duplicate out.
    CanvasObjectPlaced {
        channel_id: ChannelId,
        object: CanvasObject,
    },
}

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
        | Event::MessageEdited(_)
        | Event::MessageDeleted { .. }
        | Event::ReactionsChanged { .. }
        | Event::MessagePinned { .. }
        | Event::MessageUnpinned { .. }
        | Event::PollVoted { .. }
        | Event::TypingStarted { .. }
        | Event::TypingStopped { .. }
        | Event::PresenceChanged(_)
        | Event::CanvasObjectPlaced { .. }
        | Event::SessionRevoked(_) => false,
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
