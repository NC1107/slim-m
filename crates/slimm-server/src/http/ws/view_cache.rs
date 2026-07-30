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
//! they will get on reconnect. So this has two independent guards rather than
//! one, because the first is a list and lists rot:
//!
//! - [`ViewCache::observe`] matches [`Event`] exhaustively with no wildcard
//!   arm, so a new event variant does not compile until somebody decides
//!   whether it moves a view. That is the half a hand-kept list cannot do.
//! - Every entry also expires after [`TTL`]. The exhaustive match only covers
//!   events that exist; it says nothing about a *route* that forgets to
//!   publish one, which is the failure this codebase actually had - the
//!   2026-07-30 audit found `roles.rs`, `overwrites.rs` and `channels.rs`
//!   publishing nothing at all. The expiry turns "a permanent leak" into "at
//!   most [`TTL`] of one" without needing that never to happen again.
//!
//! An error is deliberately never cached: a transient read failure fails
//! closed for its own event and leaves nothing behind, so one blip cannot
//! silence a channel for the rest of the window.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use crate::hub::Event;
use crate::ids::{ChannelId, UserId};

/// How long an answer may be reused before it is asked again.
///
/// Short enough that a missed invalidation is a blink rather than a session,
/// and long enough that a channel taking several messages a second still asks
/// once rather than once per message, which is the whole point.
pub(super) const TTL: Duration = Duration::from_secs(5);

/// One connection's cached VIEW_CHANNEL answers, keyed by channel.
pub(super) struct ViewCache {
    viewer: UserId,
    entries: HashMap<ChannelId, Entry>,
}

struct Entry {
    visible: bool,
    asked_at: Instant,
}

impl ViewCache {
    pub(super) fn new(viewer: UserId) -> Self {
        Self {
            viewer,
            entries: HashMap::new(),
        }
    }

    /// The cached answer for `channel_id`, or `None` to go and ask.
    pub(super) fn get(&self, channel_id: ChannelId, now: Instant) -> Option<bool> {
        let entry = self.entries.get(&channel_id)?;
        (now.duration_since(entry.asked_at) < TTL).then_some(entry.visible)
    }

    pub(super) fn insert(&mut self, channel_id: ChannelId, visible: bool, now: Instant) {
        self.entries.insert(
            channel_id,
            Entry {
                visible,
                asked_at: now,
            },
        );
    }

    /// Drops whatever this event could have changed, before it is authorized.
    ///
    /// Called for every event the connection receives, including ones
    /// `authorize` answers without consulting the cache, since an event that
    /// delivers nothing can still move a later one's answer.
    ///
    /// Ordering matters and is the caller's to keep: this runs *before*
    /// `authorize`, so `OverwriteChanged` re-asks and gets the new answer,
    /// which is what lets `held_it_before` be the one thing that delivers to
    /// somebody who just lost the view.
    ///
    /// The match is exhaustive on purpose. Adding a wildcard arm would put
    /// every future event on the safe side of a decision nobody made.
    pub(super) fn observe(&mut self, event: &Event) {
        match event {
            // A role's bits moved; it is not knowable here which channels.
            Event::RoleChanged { .. } => self.entries.clear(),
            // Only a change to my own roles changes what I may view.
            Event::MemberRoleChanged { user_id, .. } if *user_id == self.viewer => {
                self.entries.clear();
            }
            // A timeout subtracts wherever permissions are read.
            Event::MemberTimeoutChanged { user_id, .. } if *user_id == self.viewer => {
                self.entries.clear();
            }
            Event::MemberRemoved(user_id) if *user_id == self.viewer => self.entries.clear(),
            Event::OverwriteChanged { channel_id, .. } => {
                self.entries.remove(channel_id);
            }
            Event::ChannelCreated(channel) | Event::ChannelUpdated(channel) => {
                self.entries.remove(&channel.id);
            }
            Event::ChannelDeleted { channel_id } => {
                self.entries.remove(channel_id);
            }
            // Somebody else's roles, timeout or removal; my answers stand.
            Event::MemberRoleChanged { .. }
            | Event::MemberTimeoutChanged { .. }
            | Event::MemberRemoved(_)
            // Traffic inside a channel never changes who may see the channel.
            | Event::MessageCreated { .. }
            | Event::MessageEdited(_)
            | Event::MessageDeleted { .. }
            | Event::ReactionsChanged { .. }
            | Event::MessagePinned { .. }
            | Event::MessageUnpinned { .. }
            | Event::PollVoted { .. }
            | Event::TypingStarted { .. }
            | Event::TypingStopped { .. }
            | Event::PresenceChanged(_)
            // The socket closes on its own revocation rather than re-asking.
            | Event::SessionRevoked(_) => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ids::RoleId;

    fn cache() -> (ViewCache, UserId, ChannelId, Instant) {
        let me = UserId::generate();
        (
            ViewCache::new(me),
            me,
            ChannelId::generate(),
            Instant::now(),
        )
    }

    /// Without this the struct could return `None` forever and every
    /// invalidation test below would still pass while nothing was cached.
    #[test]
    fn an_answer_is_reused_inside_the_window() {
        let (mut cache, _me, channel, now) = cache();
        cache.insert(channel, true, now);
        assert_eq!(cache.get(channel, now), Some(true));
        assert_eq!(
            cache.get(channel, now + TTL - Duration::from_millis(1)),
            Some(true)
        );
    }

    #[test]
    fn an_answer_expires_on_its_own() {
        let (mut cache, _me, channel, now) = cache();
        cache.insert(channel, true, now);
        assert_eq!(cache.get(channel, now + TTL), None);
    }

    #[test]
    fn a_role_edit_drops_every_channel() {
        let (mut cache, _me, channel, now) = cache();
        let other = ChannelId::generate();
        cache.insert(channel, true, now);
        cache.insert(other, true, now);
        cache.observe(&Event::RoleChanged {
            role_id: RoleId::generate(),
        });
        assert_eq!(cache.get(channel, now), None);
        assert_eq!(cache.get(other, now), None);
    }

    #[test]
    fn an_overwrite_drops_only_its_own_channel() {
        let (mut cache, _me, channel, now) = cache();
        let other = ChannelId::generate();
        cache.insert(channel, true, now);
        cache.insert(other, true, now);
        cache.observe(&Event::OverwriteChanged {
            channel_id: channel,
            previously_visible_to: Vec::new(),
        });
        assert_eq!(cache.get(channel, now), None);
        assert_eq!(cache.get(other, now), Some(true));
    }

    #[test]
    fn my_own_role_assignment_drops_everything_and_a_stranger_s_does_not() {
        let (mut cache, me, channel, now) = cache();
        cache.insert(channel, true, now);
        cache.observe(&Event::MemberRoleChanged {
            user_id: UserId::generate(),
            role_id: RoleId::generate(),
        });
        assert_eq!(
            cache.get(channel, now),
            Some(true),
            "somebody else's roles do not move my view",
        );
        cache.observe(&Event::MemberRoleChanged {
            user_id: me,
            role_id: RoleId::generate(),
        });
        assert_eq!(cache.get(channel, now), None);
    }

    #[test]
    fn my_own_timeout_drops_everything_and_a_stranger_s_does_not() {
        let (mut cache, me, channel, now) = cache();
        cache.insert(channel, true, now);
        cache.observe(&Event::MemberTimeoutChanged {
            user_id: UserId::generate(),
            until: Some(1),
        });
        assert_eq!(cache.get(channel, now), Some(true));
        cache.observe(&Event::MemberTimeoutChanged {
            user_id: me,
            until: Some(1),
        });
        assert_eq!(cache.get(channel, now), None);
    }

    #[test]
    fn ordinary_channel_traffic_keeps_the_answer() {
        let (mut cache, _me, channel, now) = cache();
        cache.insert(channel, true, now);
        cache.observe(&Event::TypingStarted {
            channel_id: channel,
            user_id: UserId::generate(),
        });
        assert_eq!(cache.get(channel, now), Some(true));
    }
}
