// SPDX-License-Identifier: AGPL-3.0-only
//! The background half of [`super::PushSender::notify_message`]: resolves
//! recipients, applies the per-recipient debounce, seals an envelope per
//! target, and calls the relay.
//!
//! Split out of `push.rs` to keep that file under the file-budget hard
//! ceiling rather than for any reason about what belongs where; every item
//! here is still `push`-private and reachable only through `super::`.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use crate::ids::{ChannelId, UserId};
use crate::store::{Store, now_ms};

use super::debounce::Debounce;
use super::{Enabled, SentMessage, envelope, message_recipients, relay};

/// How long a device's `foreground` report counts as still current. Past this
/// the app could have backgrounded or been killed without a fresh report (the
/// process was simply suspended, for instance), so treat the state as stale
/// and push anyway rather than risk a silent notification gap.
const FOREGROUND_FRESHNESS_MS: i64 = 60_000;

/// Every error path logs and returns rather than propagating: there is no
/// caller left to report to, only the process log.
///
/// The recipient rule lives in [`message_recipients`], including why the author
/// and anybody who blocked them are dropped.
///
/// The debounce is decided once per recipient, even when they have several
/// registered devices, so a second device is never mistaken for a second burst
/// trigger and dropped. A recipient filtered out for being foreground never
/// reaches that decision, so their state can never cost a different recipient
/// (or their own next genuine message) a wake; see the module docs and
/// [`Debounce`].
///
/// A window only stays shut when a recipient was really woken, which means at
/// least one of their devices took the push. Everything else releases it: a
/// batch that failed at the transport level, a recipient whose devices all
/// failed to seal (most likely a corrupt stored key), and the relay's
/// forbidden, error and not_attempted statuses. Treating any of those as
/// success would suppress that recipient's next genuine message, turning a
/// dropped wake into a silently missing notification.
///
/// A status this server does not recognize means the two repos have drifted on
/// the status vocabulary. It is handled as any other inactionable status rather
/// than crashing or misrouting, but logged, since it should never happen
/// against a relay built from the documented contract.
pub(super) async fn deliver(
    enabled: Arc<Enabled>,
    debounce: Arc<Debounce>,
    store: Store,
    sent: SentMessage,
) {
    let SentMessage {
        channel_id,
        author_id,
        message_id,
        seq,
        content,
    } = sent;
    let recipients = match message_recipients(&store, channel_id, author_id, &content).await {
        Ok(recipients) => recipients,
        Err(err) => {
            tracing::warn!(error = %err, %channel_id, "push: failed to resolve recipients");
            return;
        }
    };
    if recipients.is_empty() {
        return;
    }

    let targets = match store.push_targets(&recipients).await {
        Ok(targets) => targets,
        Err(err) => {
            tracing::warn!(error = %err, %channel_id, "push: failed to load push targets");
            return;
        }
    };

    let now = now_ms();
    let targets: Vec<_> = targets
        .into_iter()
        .filter(|target| !is_foreground_and_recent(target, now))
        .collect();
    if targets.is_empty() {
        return;
    }

    // Once per recipient, not once per device; see the note on this function.
    let mut decisions: HashMap<UserId, Option<i64>> = HashMap::new();
    for target in &targets {
        decisions
            .entry(target.user_id)
            .or_insert_with(|| debounce.try_fire(channel_id, target.user_id));
    }
    let opened: HashMap<UserId, i64> = decisions
        .into_iter()
        .filter_map(|(user_id, fired_at)| fired_at.map(|fired_at| (user_id, fired_at)))
        .collect();
    let targets: Vec<_> = targets
        .into_iter()
        .filter(|target| opened.contains_key(&target.user_id))
        .collect();
    if targets.is_empty() {
        return;
    }

    // Only when a device actually asked, so nobody opting in costs nothing.
    let preview = if targets.iter().any(|target| target.include_content) {
        message_preview(&store, channel_id, author_id, &content).await
    } else {
        None
    };

    // Read fresh here, not reused from the `now` above: sealing is what this timestamp defends.
    let sent_at = now_ms();
    let messages = envelope::seal_for_message(
        channel_id,
        message_id,
        seq,
        sent_at,
        preview.as_ref(),
        &targets,
    );

    // Nothing sealed means nothing was attempted, so release; see this function's own doc.
    for (&user_id, &fired_at) in &opened {
        if !messages.iter().any(|m| m.user_id == user_id) {
            debounce.release_if_undelivered(channel_id, user_id, fired_at);
        }
    }
    if messages.is_empty() {
        return;
    }

    match relay::send(&enabled.http, &enabled.send_url, &enabled.key, &messages).await {
        Ok(results) => {
            // Only a Delivered device counts as a wake; see this function's own doc.
            let mut delivered: HashSet<UserId> = HashSet::new();
            for result in results {
                // The relay echoes back a bare token; resolve it to the device this batch actually sent it to.
                let Some(target) = messages.iter().find(|m| m.token == result.token) else {
                    continue;
                };
                match result.parsed_status() {
                    Some(relay::RelayStatus::Delivered) => {
                        delivered.insert(target.user_id);
                    }
                    Some(relay::RelayStatus::Unregistered) => {
                        if let Err(err) = store
                            .clear_push_registration(
                                target.user_id,
                                target.device_id,
                                &result.token,
                            )
                            .await
                        {
                            tracing::warn!(error = %err, "push: failed to clear a dead registration");
                        }
                    }
                    Some(
                        relay::RelayStatus::Forbidden
                        | relay::RelayStatus::Error
                        | relay::RelayStatus::NotAttempted,
                    ) => {}
                    None => {
                        // Inactionable and logged since it should never happen; see this function's own doc.
                        tracing::warn!(
                            status = %result.status,
                            "push: relay reported a status this server does not recognize"
                        );
                    }
                }
            }
            for (&user_id, &fired_at) in &opened {
                if !delivered.contains(&user_id) {
                    debounce.release_if_undelivered(channel_id, user_id, fired_at);
                }
            }
        }
        Err(err) => {
            tracing::warn!(error = %err, %channel_id, "push: relay send failed");
            // Transport failure notified nobody, so no window may stick; see this function's own doc.
            for (&user_id, &fired_at) in &opened {
                debounce.release_if_undelivered(channel_id, user_id, fired_at);
            }
        }
    }
}

/// The sender and channel names a content-carrying envelope needs, resolved
/// once for the whole batch.
///
/// One preview serves every recipient because none of it is per-viewer:
/// blocking is already settled further up ([`message_recipients`] drops a
/// blocked author's recipients outright rather than filtering their
/// notification afterwards), and a display name and channel name are the same
/// for everybody who can see the message at all.
///
/// `None` on any failure, and on an author or channel that no longer resolves:
/// the envelope simply goes out content-free, which is exactly what every
/// device got before this existed. A preview is a nicety, and it must never be
/// the reason somebody is not woken at all.
async fn message_preview(
    store: &Store,
    channel_id: ChannelId,
    author_id: UserId,
    content: &str,
) -> Option<envelope::MessagePreview> {
    let author = match store.user_profile(author_id).await {
        Ok(Some(author)) => author,
        Ok(None) => return None,
        Err(err) => {
            tracing::warn!(error = %err, "push: failed to resolve the author for a preview");
            return None;
        }
    };
    // A DM's and a thread's channel row both carry an empty name by design.
    let channel_name = match store.channel(channel_id).await {
        Ok(channel) => channel.map(|c| c.name).unwrap_or_default(),
        Err(err) => {
            tracing::warn!(error = %err, "push: failed to resolve the channel for a preview");
            return None;
        }
    };
    Some(envelope::MessagePreview::new(
        &author.display_name,
        &channel_name,
        content,
    ))
}

/// True if a device's most recent lifecycle report says foreground and that
/// report is still fresh. WebSocket presence is deliberately not consulted
/// here: iOS suspends a socket without closing it, so a connected socket is
/// not evidence the app can show anything right now.
fn is_foreground_and_recent(target: &crate::store::PushTarget, now: i64) -> bool {
    let Some(state) = target.lifecycle_state.as_deref() else {
        return false;
    };
    let Some(reported_at) = target.lifecycle_reported_at else {
        return false;
    };
    state == "foreground" && now - reported_at < FOREGROUND_FRESHNESS_MS
}
