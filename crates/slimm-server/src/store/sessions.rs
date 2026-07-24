// SPDX-License-Identifier: AGPL-3.0-only
//! Session and token persistence: registration, login sessions, opaque access
//! and refresh tokens, and single-use WebSocket connect tickets.
//!
//! The token model has three invariants, each covered by tests:
//!
//! - Rotation. A refresh exchanges the presented token for a new refresh (same
//!   family) and a new access token, and marks the old refresh spent. The prior
//!   access token for the session is dropped in the same step. The spend is an
//!   atomic conditional UPDATE issued as the transaction's first statement, so
//!   two rotations of the same token serialize on the write lock cleanly instead
//!   of racing a stale WAL snapshot into a spurious error.
//! - Reuse detection with a grace window. Replaying a long-spent refresh token
//!   means it leaked and both the attacker and the honest client hold copies, so
//!   the whole family and its session are revoked. A replay within a short grace
//!   window is instead treated as the honest client racing itself (two tabs, a
//!   retry after a dropped response) and is denied softly without revoking, since
//!   the winning request already handed that client a fresh pair.
//! - Instant revocation. Revoking a session deletes its access tokens and
//!   connect tickets and marks its refresh tokens revoked, so a killed session's
//!   bearer token stops resolving on the next request rather than at expiry.

use sqlx::{Sqlite, SqliteConnection, Transaction};

use super::{Store, now_ms};
use crate::auth::{generate_secret, hash_secret};
use crate::ids::{DeviceId, FamilyId, SessionId, UserId};

/// Access tokens are short so a leaked one has a small window and the auth hot
/// path stays a single indexed lookup.
const ACCESS_TTL_MS: i64 = 15 * 60 * 1000;
/// Refresh tokens are long-lived but device-bound and single-use per rotation.
const REFRESH_TTL_MS: i64 = 30 * 24 * 60 * 60 * 1000;
/// Connect tickets exist only to bridge a REST auth into a WebSocket upgrade.
const WS_TICKET_TTL_MS: i64 = 30 * 1000;

/// A freshly created account.
#[derive(Debug, Clone)]
pub struct Account {
    pub id: UserId,
    pub username: String,
}

/// The secrets minted for a new or rotated session. The token fields are the
/// plaintext handed to the client once; only their hashes are stored. Not
/// `Debug`, so a secret cannot be logged by accident.
pub struct IssuedTokens {
    pub access_token: String,
    pub refresh_token: String,
    pub access_expires_at: i64,
    pub refresh_expires_at: i64,
    pub session_id: SessionId,
    pub user_id: UserId,
    pub device_id: DeviceId,
}

/// Who a validated credential resolves to. Carries no secret.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionContext {
    pub user_id: UserId,
    pub session_id: SessionId,
    pub device_id: DeviceId,
}

/// The result of presenting a refresh token.
pub enum RefreshOutcome {
    /// Accepted: here are the new access and refresh tokens.
    Rotated(IssuedTokens),
    /// Rejected for a benign reason (unknown, expired, or already revoked).
    Denied,
    /// A spent token was replayed; the family and session were revoked.
    Reused,
}

/// Why registration failed.
#[derive(Debug)]
pub enum RegisterError {
    UsernameTaken,
    Internal(anyhow::Error),
}

impl Store {
    /// Registers an account with an Argon2id password hash. A duplicate live
    /// username is reported as [`RegisterError::UsernameTaken`], not a 500.
    pub async fn create_account(
        &self,
        username: &str,
        display_name: &str,
        password_hash: &str,
    ) -> Result<Account, RegisterError> {
        let id = UserId::generate();
        let now = now_ms();
        let result = sqlx::query!(
            "INSERT INTO users (id, username, display_name, password_hash, created_at)
             VALUES (?, ?, ?, ?, ?)",
            id,
            username,
            display_name,
            password_hash,
            now
        )
        .execute(&self.pool)
        .await;

        match result {
            Ok(_) => Ok(Account {
                id,
                username: username.to_owned(),
            }),
            Err(sqlx::Error::Database(e)) if e.is_unique_violation() => {
                Err(RegisterError::UsernameTaken)
            }
            Err(e) => Err(RegisterError::Internal(e.into())),
        }
    }

    /// Looks up the user id and stored password hash for a live username, for the
    /// login path. `None` covers both no-such-user and a passwordless account.
    pub async fn find_credentials(
        &self,
        username: &str,
    ) -> anyhow::Result<Option<(UserId, String)>> {
        let row = sqlx::query!(
            r#"SELECT id AS "id!: UserId", password_hash
               FROM users
               WHERE username = ? AND deleted_at IS NULL"#,
            username
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.and_then(|r| r.password_hash.map(|hash| (r.id, hash))))
    }

    /// Opens a session for a user: a new device, a session, a refresh token in a
    /// fresh family, and the first access token, all in one transaction.
    pub async fn open_session(
        &self,
        user_id: UserId,
        device_name: &str,
    ) -> anyhow::Result<IssuedTokens> {
        let device_id = DeviceId::generate();
        let session_id = SessionId::generate();
        let family_id = FamilyId::generate();

        let access_token = generate_secret();
        let refresh_token = generate_secret();
        let access_hash = hash_secret(&access_token);
        let refresh_hash = hash_secret(&refresh_token);

        let now = now_ms();
        let access_expires_at = now + ACCESS_TTL_MS;
        let refresh_expires_at = now + REFRESH_TTL_MS;

        let mut tx = self.pool.begin().await?;
        sqlx::query!(
            "INSERT INTO devices (id, user_id, name, created_at) VALUES (?, ?, ?, ?)",
            device_id,
            user_id,
            device_name,
            now
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "INSERT INTO sessions (id, user_id, device_id, created_at) VALUES (?, ?, ?, ?)",
            session_id,
            user_id,
            device_id,
            now
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "INSERT INTO refresh_tokens (token_hash, session_id, family_id, issued_at, expires_at)
             VALUES (?, ?, ?, ?, ?)",
            refresh_hash,
            session_id,
            family_id,
            now,
            refresh_expires_at
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "INSERT INTO access_tokens (token_hash, session_id, user_id, device_id, issued_at, expires_at)
             VALUES (?, ?, ?, ?, ?, ?)",
            access_hash,
            session_id,
            user_id,
            device_id,
            now,
            access_expires_at
        )
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;

        Ok(IssuedTokens {
            access_token,
            refresh_token,
            access_expires_at,
            refresh_expires_at,
            session_id,
            user_id,
            device_id,
        })
    }

    /// Resolves a presented access token to its session, or `None` if unknown or
    /// expired. Revoked sessions have their access tokens deleted, so absence is
    /// sufficient here and this stays one indexed lookup with no join.
    pub async fn authenticate(&self, access_token: &str) -> anyhow::Result<Option<SessionContext>> {
        let hash = hash_secret(access_token);
        let now = now_ms();
        let row = sqlx::query!(
            r#"SELECT user_id AS "user_id!: UserId",
                      session_id AS "session_id!: SessionId",
                      device_id AS "device_id!: DeviceId"
               FROM access_tokens
               WHERE token_hash = ? AND expires_at > ?"#,
            hash,
            now
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|r| SessionContext {
            user_id: r.user_id,
            session_id: r.session_id,
            device_id: r.device_id,
        }))
    }

    /// Exchanges a refresh token for a new pair, detecting replay of a spent one.
    pub async fn rotate_refresh(&self, refresh_token: &str) -> anyhow::Result<RefreshOutcome> {
        let presented = hash_secret(refresh_token);
        let now = now_ms();
        let mut tx = self.pool.begin().await?;

        // Atomically spend the token as the transaction's first statement. Making
        // the first statement a write takes the write lock up front, so a
        // concurrent rotation of the same token waits on the lock and then finds
        // used_at already set, rather than both reading a NULL snapshot and one
        // failing to promote its stale snapshot to a writer. A matched row means
        // we won the claim; no row means it was unknown, revoked, expired, or
        // already spent, which `classify_failed_refresh` sorts out.
        let claimed = sqlx::query!(
            r#"UPDATE refresh_tokens SET used_at = ?
               WHERE token_hash = ? AND used_at IS NULL AND revoked_at IS NULL AND expires_at > ?
               RETURNING session_id AS "session_id!: SessionId",
                         family_id AS "family_id!: FamilyId""#,
            now,
            presented,
            now
        )
        .fetch_optional(&mut *tx)
        .await?;

        let Some(claimed) = claimed else {
            return classify_failed_refresh(tx, &presented, now, self.reuse_grace_ms).await;
        };

        // The session cannot be revoked here (revocation marks the token revoked,
        // which the claim guard excludes), but read it back for the new tokens and
        // keep the check as a belt-and-braces guard.
        let session = sqlx::query!(
            r#"SELECT user_id AS "user_id!: UserId",
                      device_id AS "device_id!: DeviceId",
                      revoked_at
               FROM sessions WHERE id = ?"#,
            claimed.session_id
        )
        .fetch_one(&mut *tx)
        .await?;
        if session.revoked_at.is_some() {
            return Ok(RefreshOutcome::Denied);
        }

        let access_token = generate_secret();
        let refresh_token = generate_secret();
        let access_hash = hash_secret(&access_token);
        let refresh_hash = hash_secret(&refresh_token);
        let access_expires_at = now + ACCESS_TTL_MS;
        let refresh_expires_at = now + REFRESH_TTL_MS;

        sqlx::query!(
            "INSERT INTO refresh_tokens (token_hash, session_id, family_id, issued_at, expires_at)
             VALUES (?, ?, ?, ?, ?)",
            refresh_hash,
            claimed.session_id,
            claimed.family_id,
            now,
            refresh_expires_at
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "DELETE FROM access_tokens WHERE session_id = ?",
            claimed.session_id
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "INSERT INTO access_tokens (token_hash, session_id, user_id, device_id, issued_at, expires_at)
             VALUES (?, ?, ?, ?, ?, ?)",
            access_hash,
            claimed.session_id,
            session.user_id,
            session.device_id,
            now,
            access_expires_at
        )
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;

        Ok(RefreshOutcome::Rotated(IssuedTokens {
            access_token,
            refresh_token,
            access_expires_at,
            refresh_expires_at,
            session_id: claimed.session_id,
            user_id: session.user_id,
            device_id: session.device_id,
        }))
    }

    /// Mints a single-use connect ticket from an already-authenticated session,
    /// returning the ticket secret and its expiry.
    pub async fn mint_ws_ticket(&self, ctx: &SessionContext) -> anyhow::Result<(String, i64)> {
        let ticket = generate_secret();
        let hash = hash_secret(&ticket);
        let now = now_ms();
        let expires_at = now + WS_TICKET_TTL_MS;
        sqlx::query!(
            "INSERT INTO ws_tickets (ticket_hash, session_id, user_id, device_id, issued_at, expires_at)
             VALUES (?, ?, ?, ?, ?, ?)",
            hash,
            ctx.session_id,
            ctx.user_id,
            ctx.device_id,
            now,
            expires_at
        )
        .execute(&self.pool)
        .await?;
        Ok((ticket, expires_at))
    }

    /// Redeems a connect ticket exactly once. Returns the session it authorizes,
    /// or `None` if the ticket is unknown, expired, already used, or its session
    /// has been revoked.
    pub async fn redeem_ws_ticket(&self, ticket: &str) -> anyhow::Result<Option<SessionContext>> {
        let hash = hash_secret(ticket);
        let now = now_ms();
        let mut tx = self.pool.begin().await?;

        // Claim the ticket atomically as the first statement, so a double
        // redemption cannot both pass the used_at check: exactly one caller
        // matches the row and marks it used.
        let claimed = sqlx::query!(
            r#"UPDATE ws_tickets SET used_at = ?
               WHERE ticket_hash = ? AND used_at IS NULL AND expires_at > ?
               RETURNING user_id AS "user_id!: UserId",
                         session_id AS "session_id!: SessionId",
                         device_id AS "device_id!: DeviceId""#,
            now,
            hash,
            now
        )
        .fetch_optional(&mut *tx)
        .await?;

        let Some(claimed) = claimed else {
            return Ok(None);
        };

        // A live ticket for a revoked session should not exist (revocation
        // deletes the session's tickets), but reject it if one somehow does.
        let session = sqlx::query!(
            r#"SELECT revoked_at FROM sessions WHERE id = ?"#,
            claimed.session_id
        )
        .fetch_optional(&mut *tx)
        .await?;
        if session.map(|s| s.revoked_at.is_some()).unwrap_or(true) {
            tx.commit().await?;
            return Ok(None);
        }
        tx.commit().await?;

        Ok(Some(SessionContext {
            user_id: claimed.user_id,
            session_id: claimed.session_id,
            device_id: claimed.device_id,
        }))
    }

    /// Revokes one session immediately (logout). Its bearer tokens stop
    /// resolving on the next request.
    pub async fn revoke_session(&self, session_id: SessionId) -> anyhow::Result<()> {
        let now = now_ms();
        let mut tx = self.pool.begin().await?;
        revoke_session_rows(&mut tx, session_id, now).await?;
        tx.commit().await?;
        Ok(())
    }

    /// Revokes every live session for a device (device removed from the account).
    /// A caller that wants any open WebSocket on those sessions closed at once
    /// must also publish `Event::SessionRevoked`, the way the logout handler does.
    pub async fn revoke_device(&self, device_id: DeviceId) -> anyhow::Result<()> {
        let now = now_ms();
        let mut tx = self.pool.begin().await?;
        sqlx::query!(
            "DELETE FROM access_tokens
             WHERE session_id IN (SELECT id FROM sessions WHERE device_id = ?)",
            device_id
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "DELETE FROM ws_tickets
             WHERE session_id IN (SELECT id FROM sessions WHERE device_id = ?)",
            device_id
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "UPDATE refresh_tokens SET revoked_at = ?
             WHERE session_id IN (SELECT id FROM sessions WHERE device_id = ?)
               AND revoked_at IS NULL",
            now,
            device_id
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "UPDATE sessions SET revoked_at = ? WHERE device_id = ? AND revoked_at IS NULL",
            now,
            device_id
        )
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(())
    }
}

/// Sorts out why a refresh claim matched no row: unknown, revoked, expired, a
/// benign within-grace concurrent retry, or a genuine reuse. Only the last
/// revokes the family and session.
async fn classify_failed_refresh(
    mut tx: Transaction<'_, Sqlite>,
    presented: &str,
    now: i64,
    reuse_grace_ms: i64,
) -> anyhow::Result<RefreshOutcome> {
    let row = sqlx::query!(
        r#"SELECT session_id AS "session_id!: SessionId",
                  family_id AS "family_id!: FamilyId",
                  used_at, revoked_at
           FROM refresh_tokens WHERE token_hash = ?"#,
        presented
    )
    .fetch_optional(&mut *tx)
    .await?;

    let Some(row) = row else {
        return Ok(RefreshOutcome::Denied); // unknown token
    };
    if row.revoked_at.is_some() {
        return Ok(RefreshOutcome::Denied); // family already revoked
    }
    let Some(used_at) = row.used_at else {
        return Ok(RefreshOutcome::Denied); // not spent, so the claim failed on expiry
    };
    if now - used_at <= reuse_grace_ms {
        // The honest client raced itself; the winning request already rotated and
        // handed it a fresh pair, so deny this one softly without revoking.
        return Ok(RefreshOutcome::Denied);
    }

    // A long-spent token was replayed: treat it as a leak and revoke everything.
    revoke_family(&mut tx, row.family_id, now).await?;
    revoke_session_rows(&mut tx, row.session_id, now).await?;
    tx.commit().await?;
    tracing::warn!(
        session_id = %row.session_id,
        "refresh token reuse detected outside the grace window; family and session revoked"
    );
    Ok(RefreshOutcome::Reused)
}

/// Marks every not-yet-revoked token in a family revoked.
async fn revoke_family(
    conn: &mut SqliteConnection,
    family_id: FamilyId,
    now: i64,
) -> anyhow::Result<()> {
    sqlx::query!(
        "UPDATE refresh_tokens SET revoked_at = ? WHERE family_id = ? AND revoked_at IS NULL",
        now,
        family_id
    )
    .execute(conn)
    .await?;
    Ok(())
}

/// Tears down a session's live credentials: access tokens and connect tickets
/// gone, refresh tokens marked revoked, and the session itself marked revoked.
async fn revoke_session_rows(
    conn: &mut SqliteConnection,
    session_id: SessionId,
    now: i64,
) -> anyhow::Result<()> {
    sqlx::query!("DELETE FROM access_tokens WHERE session_id = ?", session_id)
        .execute(&mut *conn)
        .await?;
    sqlx::query!("DELETE FROM ws_tickets WHERE session_id = ?", session_id)
        .execute(&mut *conn)
        .await?;
    sqlx::query!(
        "UPDATE refresh_tokens SET revoked_at = ? WHERE session_id = ? AND revoked_at IS NULL",
        now,
        session_id
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query!(
        "UPDATE sessions SET revoked_at = ? WHERE id = ?",
        now,
        session_id
    )
    .execute(&mut *conn)
    .await?;
    Ok(())
}
