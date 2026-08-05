// SPDX-License-Identifier: AGPL-3.0-only
//! Presence and typing glue for one WebSocket connection: the connect and
//! disconnect bookkeeping presence needs, and the inbound typing-frame
//! handling. Split out of `super` (the envelope and connection loop) so that
//! file stays focused on the wire protocol itself.

use crate::hub::{Event, Hub};
use crate::ids::{ChannelId, UserId};
use crate::permissions::Permissions;
use crate::presence::{self, Status, Visibility};
use crate::ratelimit::{Class, RateLimiter};
use crate::store::{SessionContext, Store, WORLD_LIMIT};

/// Ensures a disconnect is always recorded and published, no matter which
/// branch of the read loop in `super::serve` causes it to return: a `Drop`
/// impl runs on every exit path, including an early `return` or a panic
/// unwind, the way an explicit call at the bottom of the function could not.
pub(super) struct PresenceGuard {
    hub: Hub,
    user_id: UserId,
    idle_watch: tokio::task::AbortHandle,
}

impl PresenceGuard {
    /// Records a new live connection for `user_id` and publishes a change if
    /// this is their first (see [`crate::presence::PresenceTracker::connect`]).
    /// The returned guard must be held for the connection's whole lifetime.
    pub(super) fn connect(hub: Hub, store: Store, user_id: UserId) -> Self {
        if hub.presence().connect(user_id) {
            hub.publish(Event::PresenceChanged(user_id));
        }
        let idle_watch = tokio::spawn(watch_idle(hub.clone(), store, user_id)).abort_handle();
        Self {
            hub,
            user_id,
            idle_watch,
        }
    }
}

impl Drop for PresenceGuard {
    fn drop(&mut self) {
        self.idle_watch.abort();
        if self.hub.presence().disconnect(self.user_id) {
            self.hub.publish(Event::PresenceChanged(self.user_id));
        }
    }
}

/// Announces `user_id` crossing the idle threshold, in either direction.
///
/// Idle is purely a function of elapsed time against `PresenceTracker`'s
/// clock, not an event anything publishes on its own, so nothing would ever
/// tell a live viewer it happened otherwise: a connection that goes quiet
/// would read as online forever to everyone already watching, until some
/// unrelated event happened to touch this user's row again. Runs for the
/// connection's whole lifetime and is aborted by `PresenceGuard`'s `Drop`.
///
/// A user with several live connections runs one of these per connection,
/// all polling the one shared idle clock those connections share; a
/// transition can be published more than once for the same instant, which
/// costs one `presence_visibility` lookup plus a re-derivation per receiving
/// connection, the same trade `Hub::publish`'s own callers accept elsewhere.
///
/// **Published only for [`Visibility::Online`], and that is a privacy
/// property rather than an optimisation.** [`presence::status_for`] ignores
/// `idle` entirely for the other three, so a frame here would carry no
/// information any viewer is allowed to act on - but it would still be a
/// frame, arriving exactly when a user who chose to appear offline went quiet
/// and again when they came back. An observer timestamping frames learns
/// their activity pattern from that alone, however correct the derived status
/// is. Publishing on connect and disconnect is a narrower version of the same
/// thing and predates this; widening it to every idle transition is what this
/// avoids.
async fn watch_idle(hub: Hub, store: Store, user_id: UserId) {
    let mut ticks = tokio::time::interval(hub.idle_poll_interval());
    ticks.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let mut idle = false;
    loop {
        ticks.tick().await;
        let now_idle = hub.presence().is_idle(user_id);
        if now_idle == idle {
            continue;
        }
        idle = now_idle;
        // Read per transition, not once: visibility can change mid-connection.
        if matches!(
            store.presence_visibility(user_id).await,
            Ok(Some(Visibility::Online))
        ) {
            hub.publish(Event::PresenceChanged(user_id));
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

    // Behind the limiter, so a typing flood cannot hammer the shared presence lock.
    hub.presence().touch(ctx.user_id);

    // Same bar a send would clear; see the note on this function.
    let needed = Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES);
    match store.has_permission(ctx.user_id, channel_id, needed).await {
        Ok(true) => {}
        _ => return,
    }

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

/// Relays a pointer position on a channel's canvas, if the rate limiter,
/// bounds check and channel permissions all allow it. Silent on every
/// rejection, the same treatment [`handle_typing`] gives a refused refresh:
/// a dropped cursor frame is worth nothing, never an error frame or a closed
/// socket.
///
/// The permission bar matches the canvas HTTP routes exactly (view plus
/// `USE_CANVAS`), and there is deliberately no timeout check: a timeout
/// freezes the pen, not the mouse, the same reasoning `submit_op` already
/// gives for letting a timed-out member erase their own ink.
pub(super) async fn handle_canvas_cursor(
    store: &Store,
    hub: &Hub,
    limiter: &RateLimiter,
    ctx: &SessionContext,
    channel_id: &str,
    x: f64,
    y: f64,
) {
    let Ok(channel_id) = uuid::Uuid::parse_str(channel_id) else {
        return;
    };
    let channel_id = ChannelId(channel_id);

    if !x.is_finite() || !y.is_finite() || x.abs() > WORLD_LIMIT || y.abs() > WORLD_LIMIT {
        return;
    }

    if !limiter.check(Class::CanvasCursor, &format!("u:{}", ctx.user_id)) {
        return;
    }

    hub.presence().touch(ctx.user_id);

    let needed = Permissions::VIEW_CHANNEL.union(Permissions::USE_CANVAS);
    match store.has_permission(ctx.user_id, channel_id, needed).await {
        Ok(true) => {}
        _ => return,
    }

    hub.publish(Event::CanvasCursorMoved {
        channel_id,
        user_id: ctx.user_id,
        x,
        y,
    });
}
