// SPDX-License-Identifier: AGPL-3.0-only
//! Push registration persistence: the device attributes a push relay needs
//! (platform, token, optional VoIP token, and the device's public key), the
//! client-reported lifecycle state used to gate triggering, and the read path
//! that turns a set of recipients into the devices worth pushing to.
//!
//! Every write here is scoped to the device id from the caller's own session,
//! never one taken from the request body, and the underlying UPDATE also
//! checks `user_id`, so a forged or stale device id can only ever fail closed
//! rather than touch a foreign device's registration.

use super::{Store, now_ms};
use crate::ids::{DeviceId, UserId};

/// Why a push-registration write did not happen.
#[derive(Debug)]
pub enum PushError {
    /// No live device matched the given `(device_id, user_id)` pair, so
    /// nothing was written. This is what makes it impossible for one device
    /// to ever overwrite another device's push registration: the id pair has
    /// to actually belong together.
    NotFound,
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for PushError {
    fn from(err: sqlx::Error) -> Self {
        PushError::Internal(err.into())
    }
}

/// One device worth pushing to: its relay identity plus the key push content
/// is sealed to. Not `Debug`, so a token cannot be logged by accident.
pub struct PushTarget {
    pub user_id: UserId,
    pub device_id: DeviceId,
    pub platform: String,
    pub push_token: String,
    #[allow(dead_code)] // carried for a future call/VoIP wake path
    pub voip_push_token: Option<String>,
    pub push_public_key: Vec<u8>,
    pub lifecycle_state: Option<String>,
    pub lifecycle_reported_at: Option<i64>,
}

impl Store {
    /// Registers (or replaces) a device's push registration. Always scoped to
    /// `device_id` from the caller's own session and re-checked against
    /// `user_id` in the same `WHERE`, so a caller can never write another
    /// device's registration by supplying a foreign device id.
    ///
    /// A provider push token is a handle to one physical device, not a stable
    /// identity: a reinstall can legitimately hand the same token to a
    /// different account, or to a fresh login's device row for the same
    /// account (every login mints a new device row rather than reusing one).
    /// Whichever row registers the token now is its one true owner, so this
    /// steals it back from any other device row still holding it, in the same
    /// transaction, before writing the caller's own row. Without that, the
    /// token's previous holder would keep receiving pushes meant for its new
    /// owner until something else happened to notice.
    ///
    /// A device id that matches no row of the caller's rolls the whole
    /// transaction back, that steal included. Otherwise a caller could wipe a
    /// stranger's registration by guessing their token and any device id at
    /// all, live or not.
    pub async fn register_push(
        &self,
        user_id: UserId,
        device_id: DeviceId,
        platform: &str,
        push_token: &str,
        voip_push_token: Option<&str>,
        push_public_key: &[u8],
    ) -> Result<(), PushError> {
        let mut tx = self.pool.begin().await?;

        sqlx::query!(
            "UPDATE devices
             SET platform = NULL, push_token_ref = NULL, voip_push_token_ref = NULL,
                 push_public_key = NULL
             WHERE id != ? AND push_token_ref = ?",
            device_id,
            push_token
        )
        .execute(&mut *tx)
        .await?;

        let affected = sqlx::query!(
            "UPDATE devices
             SET platform = ?, push_token_ref = ?, voip_push_token_ref = ?, push_public_key = ?
             WHERE id = ? AND user_id = ?",
            platform,
            push_token,
            voip_push_token,
            push_public_key,
            device_id,
            user_id
        )
        .execute(&mut *tx)
        .await?
        .rows_affected();
        if affected == 0 {
            // Dropping the transaction rolls back the token reassignment
            // above; see the note on this function.
            return Err(PushError::NotFound);
        }
        tx.commit().await?;
        Ok(())
    }

    /// Clears a device's own push registration (the client opting out).
    pub async fn deregister_push(
        &self,
        user_id: UserId,
        device_id: DeviceId,
    ) -> Result<(), PushError> {
        let affected = sqlx::query!(
            "UPDATE devices
             SET platform = NULL, push_token_ref = NULL, voip_push_token_ref = NULL,
                 push_public_key = NULL
             WHERE id = ? AND user_id = ?",
            device_id,
            user_id
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        if affected == 0 {
            return Err(PushError::NotFound);
        }
        Ok(())
    }

    /// Records the client-reported lifecycle state and when it was reported.
    /// This, not WebSocket presence, is what gates whether a push is sent: a
    /// suspended-but-still-connected socket (iOS backgrounding) is not proof
    /// the app can show a notification.
    pub async fn report_lifecycle(
        &self,
        user_id: UserId,
        device_id: DeviceId,
        state: &str,
    ) -> Result<(), PushError> {
        let now = now_ms();
        let affected = sqlx::query!(
            "UPDATE devices SET lifecycle_state = ?, lifecycle_reported_at = ?
             WHERE id = ? AND user_id = ?",
            state,
            now,
            device_id,
            user_id
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        if affected == 0 {
            return Err(PushError::NotFound);
        }
        Ok(())
    }

    /// The push-capable devices for a set of users, used to fan a
    /// notification out to every recipient's registered devices. A device
    /// missing either its token or its public key is never returned: it
    /// cannot be sealed to, so it must be skipped rather than sent plaintext.
    /// Neither is a device whose session is gone: a registration otherwise
    /// outlives the session that made it, so without this a signed-out device
    /// (or a stale row left by an earlier login on the same physical device)
    /// would keep receiving push indefinitely.
    pub async fn push_targets(&self, user_ids: &[UserId]) -> anyhow::Result<Vec<PushTarget>> {
        if user_ids.is_empty() {
            return Ok(Vec::new());
        }
        // One batched query rather than one per recipient; built because the
        // id list is variable length and SQLite has no array binding, the
        // same shape roles_for_users uses.
        let mut builder = sqlx::QueryBuilder::new(
            "SELECT id, user_id, platform, push_token_ref, voip_push_token_ref, \
                    push_public_key, lifecycle_state, lifecycle_reported_at \
             FROM devices \
             WHERE push_token_ref IS NOT NULL \
               AND push_public_key IS NOT NULL AND platform IS NOT NULL \
               AND EXISTS ( \
                     SELECT 1 FROM sessions \
                      WHERE sessions.device_id = devices.id AND sessions.revoked_at IS NULL \
                   ) \
               AND user_id IN (",
        );
        let mut separated = builder.separated(", ");
        for id in user_ids {
            separated.push_bind(*id);
        }
        builder.push(")");
        let rows = builder.build().fetch_all(&self.pool).await?;

        use sqlx::Row;
        rows.into_iter()
            .map(|r| {
                Ok(PushTarget {
                    user_id: r.try_get("user_id")?,
                    device_id: r.try_get("id")?,
                    platform: r.try_get("platform")?,
                    push_token: r.try_get("push_token_ref")?,
                    voip_push_token: r.try_get("voip_push_token_ref")?,
                    push_public_key: r.try_get("push_public_key")?,
                    lifecycle_state: r.try_get("lifecycle_state")?,
                    lifecycle_reported_at: r.try_get("lifecycle_reported_at")?,
                })
            })
            .collect()
    }

    /// Everyone who has at least one device that could actually receive a push
    /// right now: a live session, a token, a key, and a platform.
    ///
    /// This is the candidate set the push trigger starts from, and it exists to
    /// keep that path off an all-users scan. Working the other way round, from
    /// every live user to the ones who can view the channel, costs a full
    /// permission evaluation (several queries) per user on every single
    /// message, whether or not anybody has push set up at all. Starting here
    /// and then filtering by view permission gives the same recipients for the
    /// price of one indexed query plus a check per candidate, and a deployment
    /// where nobody registered for push does no permission work whatsoever.
    pub async fn users_with_push_devices(&self) -> anyhow::Result<Vec<UserId>> {
        let rows = sqlx::query!(
            r#"SELECT DISTINCT user_id AS "user_id!: UserId"
               FROM devices
               WHERE push_token_ref IS NOT NULL
                 AND push_public_key IS NOT NULL AND platform IS NOT NULL
                 AND EXISTS (
                       SELECT 1 FROM sessions
                        WHERE sessions.device_id = devices.id AND sessions.revoked_at IS NULL
                     )"#
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows.into_iter().map(|r| r.user_id).collect())
    }

    /// Clears a device's push registration because the relay reported its
    /// token dead. Scoped to the specific device the caller resolved that
    /// report against (and its owning user), not to the bare token string:
    /// nothing binds a token value to one device on its own (a caller could
    /// misreport, or, before a token is uniquely re-owned on every
    /// [`Self::register_push`], two rows could transiently share one), so a
    /// token alone is never enough to identify whose registration to touch.
    /// The token is still checked too: if the device already re-registered
    /// with a fresh one before this stale report arrived, `push_token_ref` no
    /// longer matches, the `UPDATE` touches no rows, and the fresh
    /// registration is left alone.
    pub async fn clear_push_registration(
        &self,
        user_id: UserId,
        device_id: DeviceId,
        push_token: &str,
    ) -> anyhow::Result<()> {
        sqlx::query!(
            "UPDATE devices
             SET platform = NULL, push_token_ref = NULL, voip_push_token_ref = NULL,
                 push_public_key = NULL
             WHERE id = ? AND user_id = ? AND push_token_ref = ?",
            device_id,
            user_id,
            push_token
        )
        .execute(&self.pool)
        .await?;
        Ok(())
    }
}
