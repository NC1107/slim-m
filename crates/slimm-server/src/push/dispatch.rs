// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Sending a sealed batch and acting on what the relay reports back.

use super::Enabled;
use super::envelope::SealedMessage;
use super::relay::{self, RelayResult, RelayStatus};
use super::sealing::TokenSlot;
use crate::store::Store;

/// Sends `messages` and prunes every token the relay reports dead, returning the per-token
/// results for a caller that also needs them, or `None` when the relay was unreachable.
pub(super) async fn send_and_prune(
    enabled: &Enabled,
    store: &Store,
    messages: &[SealedMessage],
    what: &'static str,
) -> Option<Vec<RelayResult>> {
    if messages.is_empty() {
        return Some(Vec::new());
    }
    let results = match relay::send(&enabled.http, &enabled.send_url, &enabled.key, messages).await
    {
        Ok(results) => results,
        Err(err) => {
            tracing::warn!(error = %err, what, "push: relay send failed");
            return None;
        }
    };
    for result in &results {
        if result.parsed_status() != Some(RelayStatus::Unregistered) {
            continue;
        }
        // The relay echoes back a bare token; resolve it to the device this batch sent it to.
        if let Some(message) = messages.iter().find(|m| m.token == result.token) {
            clear_dead(store, message).await;
        }
    }
    Some(results)
}

/// Clears the one token the relay reported dead, never the device's other one.
pub(super) async fn clear_dead(store: &Store, message: &SealedMessage) {
    let cleared = match message.slot {
        TokenSlot::Push => {
            store
                .clear_push_registration(message.user_id, message.device_id, &message.token)
                .await
        }
        TokenSlot::Voip => {
            store
                .clear_voip_push_token(message.user_id, message.device_id, &message.token)
                .await
        }
    };
    if let Err(err) = cleared {
        tracing::warn!(error = %err, "push: failed to clear a dead registration");
    }
}
