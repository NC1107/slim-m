// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Waking a backgrounded phone for an incoming DM call ring.
//!
//! [`deliver`] mirrors `deliver.rs`'s message path trimmed to what a ring
//! actually needs: exactly one recipient, and no debounce - a ring fires once
//! per attempt, never in the kind of burst a message send can produce, so
//! there is nothing here for a debounce window to collapse.
//!
//! The envelope shares [`envelope::seal_for_message`]'s sealing machinery
//! (the domain, version, byte budget and per-target key handling all live in
//! `envelope.rs`) but not its content-free/with-content split for a *body*:
//! a ring carries no message text, only who is calling. [`CallRingEnvelope`]
//! is this module's own shape for that: `channel_id`, `ring_id` and
//! `caller_id` ride unconditionally (a receiving device could already
//! resolve who is calling from `channel_id` alone, since a DM has exactly
//! one other participant), while `caller_name` is gated behind
//! [`PushTarget::include_content`] exactly as a message's own sender name is.
//!
//! Quiet hours are not consulted here, deliberately. `push::recipients`'s own
//! notification-preference narrowing only ever demotes
//! [`NotificationPreference::Everything`] to [`NotificationPreference::Mentions`],
//! and `Mentions` already lets every DM through - a direct call is at least
//! as addressed-to-you as an ordinary DM message, so it is never muted by a
//! quiet window either. The one preference that does suppress a ring is
//! [`NotificationPreference::Nothing`]: an account that opted out of every
//! notification, DMs included, also opted out of being rung.

use std::sync::Arc;

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use crypto_box::PublicKey;
use crypto_box::aead::rand_core::{OsRng, TryRngCore};
use serde::Serialize;

use crate::ids::{CallRingId, ChannelId, UserId};
use crate::notifications::NotificationPreference;
use crate::store::{Store, now_ms};

use super::deliver::is_foreground_and_recent;
use super::envelope::{
    DOMAIN, ENVELOPE_VERSION, MAX_ENVELOPE_PLAINTEXT_BYTES, MAX_PREVIEW_NAME_CHARS,
    PUBLIC_KEY_BYTES, PushKind, SealedMessage, truncate,
};
use super::{Enabled, relay};

/// Delivers a push for one DM call ring to its one callee.
///
/// Every error path logs and returns rather than propagating, the same
/// contract `deliver::deliver` follows: there is no caller left to report to,
/// only the process log, and the live WebSocket ring already reached a
/// connected client regardless of whether this push ever lands.
pub(super) async fn deliver(
    enabled: Arc<Enabled>,
    store: Store,
    channel_id: ChannelId,
    ring_id: CallRingId,
    caller_id: UserId,
    callee_id: UserId,
) {
    let preference = match store
        .channel_notification_preferences(channel_id, &[callee_id])
        .await
    {
        Ok(preferences) => preferences.get(&callee_id).copied().unwrap_or_default(),
        Err(err) => {
            tracing::warn!(error = %err, %channel_id, "push: failed to resolve a call ring's notification preference");
            return;
        }
    };
    // Only an outright opt-out suppresses a ring; see this module's own doc.
    if preference == NotificationPreference::Nothing {
        return;
    }

    let targets = match store.push_targets(&[callee_id]).await {
        Ok(targets) => targets,
        Err(err) => {
            tracing::warn!(error = %err, %channel_id, "push: failed to load a call ring's push targets");
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

    let caller_name = match store.user_profile(caller_id).await {
        Ok(Some(profile)) => Some(profile.display_name),
        Ok(None) => None,
        Err(err) => {
            tracing::warn!(error = %err, "push: failed to resolve a call ring's caller name");
            None
        }
    };

    let sent_at = now_ms();
    let messages = seal_for_call_ring(
        channel_id,
        ring_id,
        caller_id,
        caller_name.as_deref(),
        sent_at,
        &targets,
    );
    if messages.is_empty() {
        return;
    }

    if let Err(err) = relay::send(&enabled.http, &enabled.send_url, &enabled.key, &messages).await {
        tracing::warn!(error = %err, %channel_id, "push: relay send failed for a call ring");
    }
}

/// The sealed plaintext for a DM call ring.
#[derive(Serialize)]
struct CallRingEnvelope<'a> {
    domain: &'static str,
    version: u8,
    kind: PushKind,
    channel_id: String,
    ring_id: String,
    caller_id: String,
    sent_at: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    caller_name: Option<&'a str>,
}

/// Seals a DM call ring notification to every target's public key, the same
/// per-device sealing [`envelope::seal_for_message`] does for a message.
fn seal_for_call_ring(
    channel_id: ChannelId,
    ring_id: CallRingId,
    caller_id: UserId,
    caller_name: Option<&str>,
    sent_at: i64,
    targets: &[crate::store::PushTarget],
) -> Vec<SealedMessage> {
    let Some(bare) = encode(channel_id, ring_id, caller_id, sent_at, None) else {
        return Vec::new();
    };
    let with_content = caller_name
        .and_then(|name| encode(channel_id, ring_id, caller_id, sent_at, Some(name)))
        .filter(|plaintext| plaintext.len() <= MAX_ENVELOPE_PLAINTEXT_BYTES);

    let mut sealed = Vec::with_capacity(targets.len());
    for target in targets {
        let Ok(key_bytes) = <[u8; PUBLIC_KEY_BYTES]>::try_from(target.push_public_key.as_slice())
        else {
            tracing::warn!(
                device_id = %target.device_id,
                "push: stored public key is the wrong size, skipping this device"
            );
            continue;
        };
        let public_key = PublicKey::from_bytes(key_bytes);

        let plaintext = match (target.include_content, &with_content) {
            (true, Some(with_content)) => with_content,
            _ => &bare,
        };

        let Ok(ciphertext) = public_key.seal(&mut OsRng.unwrap_err(), plaintext) else {
            tracing::warn!(device_id = %target.device_id, "push: sealing failed, skipping this device");
            continue;
        };

        sealed.push(SealedMessage {
            user_id: target.user_id,
            device_id: target.device_id,
            platform: target.platform.clone(),
            token: target.push_token.clone(),
            kind: PushKind::Call.wire_str(),
            payload: BASE64.encode(ciphertext),
        });
    }
    sealed
}

fn encode(
    channel_id: ChannelId,
    ring_id: CallRingId,
    caller_id: UserId,
    sent_at: i64,
    caller_name: Option<&str>,
) -> Option<Vec<u8>> {
    let truncated_name = caller_name.map(|name| truncate(name, MAX_PREVIEW_NAME_CHARS, false));
    let envelope = CallRingEnvelope {
        domain: DOMAIN,
        version: ENVELOPE_VERSION,
        kind: PushKind::Call,
        channel_id: channel_id.to_string(),
        ring_id: ring_id.to_string(),
        caller_id: caller_id.to_string(),
        sent_at,
        caller_name: truncated_name.as_deref(),
    };
    match serde_json::to_vec(&envelope) {
        Ok(bytes) => Some(bytes),
        Err(err) => {
            tracing::error!(error = %err, "push: call ring envelope failed to serialize");
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `channel_id`, `ring_id` and `caller_id` are never content: every
    /// device gets them regardless of `include_content`, since a receiving
    /// device could already resolve who is calling from `channel_id` alone.
    #[test]
    fn ids_ride_unconditionally_but_the_name_does_not() {
        let bare = encode(
            ChannelId::generate(),
            CallRingId::generate(),
            UserId::generate(),
            1_700_000_000_000,
            None,
        )
        .expect("encodes");
        let value: serde_json::Value = serde_json::from_slice(&bare).expect("valid json");
        assert_eq!(value["kind"], "call");
        assert!(value.get("caller_name").is_none());

        let with_name = encode(
            ChannelId::generate(),
            CallRingId::generate(),
            UserId::generate(),
            1_700_000_000_000,
            Some("Ada"),
        )
        .expect("encodes");
        let value: serde_json::Value = serde_json::from_slice(&with_name).expect("valid json");
        assert_eq!(value["caller_name"], "Ada");
    }

    /// Nothing here is variable-length except three uuids, a `caller_id` and
    /// a `sent_at`, so the content-free envelope always has to fit - the same
    /// property `envelope::tests::the_content_free_envelope_always_fits_the_budget`
    /// pins for a message.
    #[test]
    fn the_content_free_envelope_always_fits_the_budget() {
        let bare = encode(
            ChannelId::generate(),
            CallRingId::generate(),
            UserId::generate(),
            i64::MAX,
            None,
        )
        .expect("the content-free ring envelope always encodes");
        assert!(bare.len() <= MAX_ENVELOPE_PLAINTEXT_BYTES);
    }
}
