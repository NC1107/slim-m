// SPDX-License-Identifier: AGPL-3.0-only
//! The content-free push envelope: the only thing the relay, and the APNs and
//! FCM infrastructure it forwards through, ever sees.
//!
//! The plaintext names nothing about the message: no text, no author, no
//! channel name. Just enough for the receiving device to know it should
//! reconnect and catch up over `/sync`. It is sealed with a libsodium-style
//! anonymous sealed box (X25519 plus XSalsa20Poly1305): encrypted to the
//! device's registered public key, with no sender identity of its own, which
//! is the right shape here since the server is not a party the device needs
//! to authenticate, only a courier.

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use crypto_box::PublicKey;
use crypto_box::aead::rand_core::{OsRng, TryRngCore};
use serde::Serialize;

use crate::ids::{ChannelId, DeviceId, MessageId, Seq, UserId};
use crate::store::PushTarget;

/// Domain-separates this plaintext from anything else that might ever be
/// sealed to the same device key, so a payload from a different context can
/// never be reinterpreted as a push envelope.
const DOMAIN: &str = "slim-m.push.v1";
const ENVELOPE_VERSION: u8 = 1;

/// X25519 public keys are exactly 32 bytes.
const PUBLIC_KEY_BYTES: usize = 32;

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "lowercase")]
enum PushKind {
    Message,
}

impl PushKind {
    /// The relay's own `kind` field, a separate string from this envelope's
    /// serialized form (which lives inside the sealed, opaque payload).
    fn wire_str(self) -> &'static str {
        match self {
            PushKind::Message => "message",
        }
    }
}

#[derive(Serialize)]
struct PushEnvelope {
    domain: &'static str,
    version: u8,
    kind: PushKind,
    channel_id: String,
    message_id: String,
    seq: i64,
}

impl PushEnvelope {
    fn for_message(channel_id: ChannelId, message_id: MessageId, seq: Seq) -> Self {
        Self {
            domain: DOMAIN,
            version: ENVELOPE_VERSION,
            kind: PushKind::Message,
            channel_id: channel_id.to_string(),
            message_id: message_id.to_string(),
            seq: seq.0,
        }
    }
}

/// One relay-bound message: a target's platform and token, the relay's own
/// `kind`, and the sealed, base64-encoded envelope. Deliberately not `Debug`:
/// `token` and `payload` are exactly what must never be logged.
///
/// `user_id` and `device_id` never leave this process (the relay is never
/// told them); they let the caller map a relay result and its bare `token`
/// back to the exact device it was actually sent to, for per-recipient
/// debounce bookkeeping and for scoping a dead-token clear to that device
/// rather than trusting the token string alone.
pub(super) struct SealedMessage {
    pub(super) user_id: UserId,
    pub(super) device_id: DeviceId,
    pub(super) platform: String,
    pub(super) token: String,
    pub(super) kind: &'static str,
    pub(super) payload: String,
}

/// Seals a new-message notification to every target's public key.
///
/// A target is skipped, not sent plaintext, if its stored key cannot be
/// parsed as an X25519 public key: a corrupt key means that one device cannot
/// receive push until it re-registers, not that the batch should fail or fall
/// back to something unencrypted.
///
/// Each sealed box draws its own randomness. There is no long-lived secret
/// here for a bad RNG to compromise beyond one message's onward
/// confidentiality, but `OsRng` is what the rest of this codebase already
/// trusts for key and token generation, so it is what this uses too.
pub(super) fn seal_for_message(
    channel_id: ChannelId,
    message_id: MessageId,
    seq: Seq,
    targets: &[PushTarget],
) -> Vec<SealedMessage> {
    let envelope = PushEnvelope::for_message(channel_id, message_id, seq);
    let plaintext = match serde_json::to_vec(&envelope) {
        Ok(bytes) => bytes,
        Err(err) => {
            tracing::error!(error = %err, "push: envelope failed to serialize, dropping batch");
            return Vec::new();
        }
    };

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

        // Fresh randomness per sealed box, from the same OsRng this codebase
        // already trusts for key and token generation.
        let Ok(ciphertext) = public_key.seal(&mut OsRng.unwrap_err(), &plaintext) else {
            tracing::warn!(device_id = %target.device_id, "push: sealing failed, skipping this device");
            continue;
        };

        sealed.push(SealedMessage {
            user_id: target.user_id,
            device_id: target.device_id,
            platform: target.platform.clone(),
            token: target.push_token.clone(),
            kind: envelope.kind.wire_str(),
            payload: BASE64.encode(ciphertext),
        });
    }
    sealed
}
