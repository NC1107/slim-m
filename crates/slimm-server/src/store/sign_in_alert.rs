// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Deciding whether a sign-in is worth telling the account about.

use super::{Store, now_ms};
use crate::ids::{DeviceId, UserId};

impl Store {
    /// Whether the sign-in that just minted `device_id` should alert the
    /// account's other devices.
    ///
    /// Every login mints a fresh device row, so "a device we have seen" cannot
    /// mean the same row: it means an earlier row (live or long expired) with
    /// the same name and client kind, the pair a client reports about itself.
    /// The first device of an account has no one to tell, so it needs another
    /// *live* device to alert. The liveness clause matches
    /// [`Store::list_devices`], so the alert never targets a device the owner
    /// can no longer see or sign out.
    pub async fn is_unfamiliar_sign_in(
        &self,
        user_id: UserId,
        device_id: DeviceId,
        device_name: &str,
        client_kind: Option<&str>,
    ) -> anyhow::Result<bool> {
        let now = now_ms();
        let unfamiliar = sqlx::query_scalar!(
            r#"SELECT (
                 EXISTS (
                   SELECT 1 FROM devices d
                   WHERE d.user_id = ? AND d.id != ?
                     AND EXISTS (
                       SELECT 1 FROM sessions s
                       JOIN refresh_tokens r ON r.session_id = s.id
                       WHERE s.device_id = d.id
                         AND s.revoked_at IS NULL
                         AND r.used_at IS NULL
                         AND r.revoked_at IS NULL
                         AND r.expires_at > ?
                     )
                 )
                 AND NOT EXISTS (
                   SELECT 1 FROM devices d
                   WHERE d.user_id = ? AND d.id != ?
                     AND d.name = ? AND d.client_kind IS ?
                 )
               ) AS "unfamiliar!: bool""#,
            user_id,
            device_id,
            now,
            user_id,
            device_id,
            device_name,
            client_kind
        )
        .fetch_one(&self.pool)
        .await?;
        Ok(unfamiliar)
    }
}
