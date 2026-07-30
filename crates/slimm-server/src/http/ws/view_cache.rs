// SPDX-License-Identifier: AGPL-3.0-only
//! One connection's memory of which channels its viewer may see.
//!
//! `authorize` asks `has_permission` once per delivered event, and that
//! resolves to five queries (channel, two role queries, overwrites, timeout
//! deny), six on a typing frame. `MAX_CONNECTIONS` is 1024 against a read pool
//! of 8 shared with the write path, so a busy channel spends most of the pool
//! re-deriving an answer that changes far more rarely than messages arrive.
//!
//! Only VIEW_CHANNEL is cached. It is the one bit `authorize` asks for, and
//! caching a whole permission set would mean invalidating on things that
//! cannot change who receives a frame.
//!
//! **The dangerous direction is one-way.** A stale `true` delivers an event to
//! somebody whose view was just revoked; a stale `false` merely withholds one
//! they will get on reconnect. Two things bound it:
//!
//! - **[`Hub::permissions_epoch`], which is what makes this correct.** An
//!   entry is only reused while the epoch it was taken at still stands, and
//!   the hub bumps that inside `publish`, before the send. So a revocation
//!   invalidates every connection's entries the moment the publishing request
//!   reaches its publish call, with no dependence on when - or in what order -
//!   any connection receives the event.
//!
//!   Keying on the events themselves was tried first and is wrong, which is
//!   worth recording because it looks right. Delivery order across concurrent
//!   writers is best-effort (`hub.rs`'s own module doc says so), so a
//!   connection can be handed a `message.created` from one request before the
//!   `overwrite.changed` from another that had already committed. Invalidating
//!   as each event arrives leaves the pre-revocation answer serving that
//!   message, and every other one that wins the same race.
//!
//! - **[`TTL`], as the outer backstop.** The epoch only moves for events that
//!   are published; it says nothing about a route that writes permissions and
//!   publishes nothing, which is the failure this codebase actually had - the
//!   2026-07-30 audit found `roles.rs`, `overwrites.rs` and `channels.rs`
//!   publishing nothing at all, and invite redemption still grants a role with
//!   no event. Expiry turns "a permanent leak" into "at most [`TTL`] of one".
//!
//! The residual is the gap between a handler's commit and its `publish` call.
//! No handler that publishes a permission event has an await between the two,
//! so it is a few instructions with nothing scheduled in between, rather than
//! a window another task can be woken inside.
//!
//! An error is deliberately never cached: a transient read failure fails
//! closed for its own event and leaves nothing behind, so one blip cannot
//! silence a channel for the rest of the window.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use crate::ids::ChannelId;

/// How long an answer may be reused before it is asked again.
///
/// Short enough that a permission write nothing published is a blink rather
/// than a session, and long enough that a channel taking several messages a
/// second still asks once rather than once per message.
pub(super) const TTL: Duration = Duration::from_secs(5);

/// One connection's cached VIEW_CHANNEL answers, keyed by channel.
pub(super) struct ViewCache {
    entries: HashMap<ChannelId, Entry>,
}

struct Entry {
    visible: bool,
    asked_at: Instant,
    epoch: u64,
}

impl ViewCache {
    pub(super) fn new() -> Self {
        Self {
            entries: HashMap::new(),
        }
    }

    /// The cached answer for `channel_id`, or `None` to go and ask.
    ///
    /// Both conditions are necessary: `epoch` catches a permission change that
    /// was published, however the events happen to interleave, and `now`
    /// catches one that was not.
    pub(super) fn get(&self, channel_id: ChannelId, now: Instant, epoch: u64) -> Option<bool> {
        let entry = self.entries.get(&channel_id)?;
        let fresh = now.duration_since(entry.asked_at) < TTL && entry.epoch == epoch;
        fresh.then_some(entry.visible)
    }

    /// Records an answer against the epoch it was derived under.
    ///
    /// The caller must read the epoch *before* asking the store, not after: an
    /// epoch read afterwards could belong to a write that landed during the
    /// query, and the answer would be filed as newer than it is.
    pub(super) fn insert(
        &mut self,
        channel_id: ChannelId,
        visible: bool,
        now: Instant,
        epoch: u64,
    ) {
        self.entries.insert(
            channel_id,
            Entry {
                visible,
                asked_at: now,
                epoch,
            },
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cache() -> (ViewCache, ChannelId, Instant) {
        (ViewCache::new(), ChannelId::generate(), Instant::now())
    }

    /// Without this the struct could return `None` forever and every
    /// invalidation test below would still pass while nothing was cached.
    #[test]
    fn an_answer_is_reused_inside_the_window() {
        let (mut cache, channel, now) = cache();
        cache.insert(channel, true, now, 7);
        assert_eq!(cache.get(channel, now, 7), Some(true));
        assert_eq!(
            cache.get(channel, now + TTL - Duration::from_millis(1), 7),
            Some(true)
        );
    }

    #[test]
    fn an_answer_expires_on_its_own() {
        let (mut cache, channel, now) = cache();
        cache.insert(channel, true, now, 7);
        assert_eq!(cache.get(channel, now + TTL, 7), None);
    }

    /// The load-bearing one: a permission write moves the epoch, and that
    /// alone drops the answer with no event having been received.
    #[test]
    fn a_moved_epoch_drops_the_answer_immediately() {
        let (mut cache, channel, now) = cache();
        cache.insert(channel, true, now, 7);
        assert_eq!(cache.get(channel, now, 8), None);
    }

    /// An epoch that moved and moved back is still a different answer: the
    /// counter only ever climbs, so this can only mean two writes happened.
    #[test]
    fn every_channel_answers_to_the_same_epoch() {
        let (mut cache, channel, now) = cache();
        let other = ChannelId::generate();
        cache.insert(channel, true, now, 7);
        cache.insert(other, false, now, 7);
        assert_eq!(cache.get(channel, now, 8), None);
        assert_eq!(cache.get(other, now, 8), None);
    }

    #[test]
    fn an_unknown_channel_is_never_a_hit() {
        let (cache, channel, now) = cache();
        assert_eq!(cache.get(channel, now, 0), None);
    }
}
