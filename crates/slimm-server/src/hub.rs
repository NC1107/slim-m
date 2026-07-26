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
use std::time::Duration;

use tokio::sync::{OwnedSemaphorePermit, Semaphore, broadcast};

use crate::ids::{ChannelId, MessageId, SessionId, UserId};
use crate::presence::PresenceTracker;
use crate::store::Message;
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
    MessageCreated(Message),
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
    /// A message's reactions changed. Carries the whole public summary rather
    /// than a delta, so a client that missed a frame cannot drift; the
    /// per-viewer "did I react" flag is deliberately not broadcast.
    ReactionsChanged {
        channel_id: ChannelId,
        message_id: MessageId,
        reactions: Vec<(String, i64)>,
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
        }
    }

    /// Builds a hub with a non-default typing TTL, so a test can wait out the
    /// self-expiry in milliseconds instead of the production few seconds.
    pub fn with_typing_ttl(ttl: Duration) -> Self {
        let (sender, _receiver) = broadcast::channel(CHANNEL_CAPACITY);
        Self {
            sender,
            slots: Arc::new(Semaphore::new(MAX_CONNECTIONS)),
            presence: PresenceTracker::new(),
            typing: TypingTracker::with_ttl(ttl),
        }
    }

    /// Publishes an event to every current subscriber. Does nothing if there are
    /// none; never blocks or errors from the caller's point of view.
    pub fn publish(&self, event: Event) {
        let _ = self.sender.send(event);
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
