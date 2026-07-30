// SPDX-License-Identifier: AGPL-3.0-only
//! Presence and typing glue for one WebSocket connection: the connect and
//! disconnect bookkeeping presence needs, and the inbound typing-frame
//! handling. Split out of `super` (the envelope and connection loop) so that
//! file stays focused on the wire protocol itself.

use crate::hub::{Event, Hub};
use crate::ids::{ChannelId, UserId};
use crate::permissions::Permissions;
use crate::presence::{self, Status};
use crate::ratelimit::{Class, RateLimiter};
use crate::store::{SessionContext, Store};

/// Ensures a disconnect is always recorded and published, no matter which
/// branch of the read loop in `super::serve` causes it to return: a `Drop`
/// impl runs on every exit path, including an early `return` or a panic
/// unwind, the way an explicit call at the bottom of the function could not.
pub(super) struct PresenceGuard {
    hub: Hub,
    user_id: UserId,
}

impl PresenceGuard {
    /// Records a new live connection for `user_id` and publishes a change if
    /// this is their first (see [`crate::presence::PresenceTracker::connect`]).
    /// The returned guard must be held for the connection's whole lifetime.
    pub(super) fn connect(hub: Hub, user_id: UserId) -> Self {
        if hub.presence().connect(user_id) {
            hub.publish(Event::PresenceChanged(user_id));
        }
        Self { hub, user_id }
    }
}

impl Drop for PresenceGuard {
    fn drop(&mut self) {
        if self.hub.presence().disconnect(self.user_id) {
            self.hub.publish(Event::PresenceChanged(self.user_id));
        }
    }
}

/// Resolves what `viewer` may be told about `target`'s live presence.
///
/// `Ok(None)` only if `target`'s account is gone: a fan-out racing an account
/// deletion should not synthesize presence for it. `Err` means the store
/// could not answer at all, and is kept distinct from `Ok(None)` on purpose:
/// a caller with something to protect (see `authorize`'s typing branch in
/// `super`) must be able to fail closed on a blip without that blip reading
/// as an ordinary "account gone" answer.
pub(super) async fn presence_status(
    store: &Store,
    hub: &Hub,
    viewer: UserId,
    target: UserId,
) -> anyhow::Result<Option<Status>> {
    let Some(visibility) = store.presence_visibility(target).await? else {
        return Ok(None);
    };
    let tracker = hub.presence();
    Ok(Some(presence::status_for(
        viewer,
        target,
        visibility,
        tracker.is_connected(target),
        tracker.is_idle(target),
    )))
}

/// Accepts a typing refresh from `ctx`'s user for `channel_id`, if the rate
/// limiter and channel permissions allow it. Silent on every rejection:
/// typing is a low-stakes hint, not worth an error frame or closing the
/// socket over.
///
/// The permission bar is the same one a send would have to clear: viewing is
/// required so this cannot probe for a channel's existence, and sending is
/// required so a read-only member cannot show up as "about to post" somewhere
/// they could not.
pub(super) async fn handle_typing(
    store: &Store,
    hub: &Hub,
    limiter: &RateLimiter,
    ctx: &SessionContext,
    channel_id: &str,
) {
    let Ok(channel_id) = uuid::Uuid::parse_str(channel_id) else {
        return;
    };
    let channel_id = ChannelId(channel_id);

    if !limiter.check(Class::Typing, &format!("u:{}", ctx.user_id)) {
        return;
    }

    // Same bar a send would clear; see the note on this function.
    let needed = Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES);
    match store.has_permission(ctx.user_id, channel_id, needed).await {
        Ok(true) => {}
        _ => return,
    }

    hub.presence().touch(ctx.user_id);

    let (generation, is_new) = hub.typing().start(channel_id, ctx.user_id);
    if is_new {
        hub.publish(Event::TypingStarted {
            channel_id,
            user_id: ctx.user_id,
        });
    }

    // Self-expiry, one per refresh and a no-op once a later refresh bumps the
    // generation past this one (`crate::typing::TypingTracker::expire`).
    let hub = hub.clone();
    let ttl = hub.typing().ttl();
    let user_id = ctx.user_id;
    tokio::spawn(async move {
        tokio::time::sleep(ttl).await;
        if hub.typing().expire(channel_id, user_id, generation) {
            hub.publish(Event::TypingStopped {
                channel_id,
                user_id,
            });
        }
    });
}
