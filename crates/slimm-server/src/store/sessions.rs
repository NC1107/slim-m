// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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

use super::invites::{record_redemption, spend_invite};
use super::{JoinPolicy, Store, now_ms};
use crate::auth::{generate_secret, hash_secret};
use crate::ids::{DeviceId, FamilyId, SessionId, UserId};

/// Access tokens are short so a leaked one has a small window and the auth hot
/// path stays a single indexed lookup.
const ACCESS_TTL_MS: i64 = 15 * 60 * 1000;
/// Refresh tokens are long-lived but device-bound and single-use per rotation.
const REFRESH_TTL_MS: i64 = 30 * 24 * 60 * 60 * 1000;
/// Connect tickets exist only to bridge a REST auth into a WebSocket upgrade.
const WS_TICKET_TTL_MS: i64 = 30 * 1000;

/// How long past its own expiry a refresh token is kept before being swept.
///
/// Not zero, and not tunable down casually: reuse detection works by finding
/// the spent row and noticing `used_at` is set (see [`Store::rotate_refresh`]).
/// Delete the row and a replayed token stops being distinguishable from one
/// that never existed, so the family is denied softly instead of being revoked
/// as leaked. Keeping a full extra `REFRESH_TTL_MS` past expiry means anything
/// still worth detecting is still there: by then the token has been unusable
/// for a month and the attacker has had nothing to gain from it for as long.
const REFRESH_SWEEP_GRACE_MS: i64 = REFRESH_TTL_MS;

/// How long past expiry a spent or stale connect ticket is kept. Single use is
/// enforced by `used_at` inside the 30-second window, so nothing after that
/// window depends on the row existing; the hour is slack for clock skew.
const TICKET_SWEEP_GRACE_MS: i64 = 60 * 60 * 1000;

/// How long past expiry an access token row is kept. Authorization already
/// checks `expires_at`, so an expired row grants nothing; the day is slack.
const ACCESS_SWEEP_GRACE_MS: i64 = 24 * 60 * 60 * 1000;

/// How many rows one sweep deletes per table.
///
/// Bounded so the sweep cannot take the write lock for an unbounded stretch on
/// a deployment that has gone a long time without one. Whatever it does not
/// reach this pass, it reaches on the next.
const SWEEP_BATCH: i64 = 5_000;

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
    /// The deployment has been claimed, so joining is by invitation and no code
    /// was presented.
    InviteRequired,
    /// A code was presented but is expired, spent, revoked, or never existed.
    /// One variant for all four, so registration cannot be used to mine codes.
    InviteUnusable,
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for RegisterError {
    fn from(err: sqlx::Error) -> Self {
        RegisterError::Internal(err.into())
    }
}

impl From<anyhow::Error> for RegisterError {
    fn from(err: anyhow::Error) -> Self {
        RegisterError::Internal(err)
    }
}

/// Why opening a session failed.
#[derive(Debug)]
pub enum OpenError {
    /// The account was deleted between the credential check and session creation,
    /// so no session may be issued for it.
    AccountGone,
    /// The account is live and the password was right, but a moderator has
    /// removed this member from the Space.
    ///
    /// Told apart from [`Self::AccountGone`] because the two want different
    /// words in front of a person: one is "this account no longer exists" and
    /// the other is "you were removed", and offering the first for the second
    /// sends somebody to create a duplicate account to fix it.
    Removed,
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for OpenError {
    fn from(err: sqlx::Error) -> Self {
        OpenError::Internal(err.into())
    }
}

/// What one sweep removed, so the caller can log something meaningful and a
/// test can assert on it.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct SweptTokens {
    pub access_tokens: u64,
    pub refresh_tokens: u64,
    pub ws_tickets: u64,
}

impl SweptTokens {
    pub fn total(self) -> u64 {
        self.access_tokens + self.refresh_tokens + self.ws_tickets
    }
}

impl Store {
    /// Deletes token rows that are far enough past their expiry to be useless.
    ///
    /// Every sign-in writes an access token and a refresh token, every rotation
    /// writes another refresh token, and every socket connect writes a ticket.
    /// Nothing deleted any of them except the targeted revocation paths, so all
    /// three tables grew for the life of a deployment and never shrank, taking
    /// the indexes over them along for the ride.
    ///
    /// Each grace window is chosen so nothing that still means something is
    /// removed; see the constants for why, particularly
    /// [`REFRESH_SWEEP_GRACE_MS`], which reuse detection depends on.
    ///
    /// The three deletes are separate statements rather than one transaction:
    /// the tables are independent, and holding the write lock across all three
    /// buys nothing while making the pause longer.
    pub async fn sweep_expired_tokens(&self) -> anyhow::Result<SweptTokens> {
        let now = now_ms();
        let access_cutoff = now - ACCESS_SWEEP_GRACE_MS;
        let refresh_cutoff = now - REFRESH_SWEEP_GRACE_MS;
        let ticket_cutoff = now - TICKET_SWEEP_GRACE_MS;

        // Three statements, not one transaction; see the note on this function.
        let access_tokens = sqlx::query!(
            "DELETE FROM access_tokens WHERE rowid IN
             (SELECT rowid FROM access_tokens WHERE expires_at < ? LIMIT ?)",
            access_cutoff,
            SWEEP_BATCH
        )
        .execute(&self.pool)
        .await?
        .rows_affected();

        let refresh_tokens = sqlx::query!(
            "DELETE FROM refresh_tokens WHERE rowid IN
             (SELECT rowid FROM refresh_tokens WHERE expires_at < ? LIMIT ?)",
            refresh_cutoff,
            SWEEP_BATCH
        )
        .execute(&self.pool)
        .await?
        .rows_affected();

        let ws_tickets = sqlx::query!(
            "DELETE FROM ws_tickets WHERE rowid IN
             (SELECT rowid FROM ws_tickets WHERE expires_at < ? LIMIT ?)",
            ticket_cutoff,
            SWEEP_BATCH
        )
        .execute(&self.pool)
        .await?
        .rows_affected();

        Ok(SweptTokens {
            access_tokens,
            refresh_tokens,
            ws_tickets,
        })
    }

    /// Registers an account through the front door: the deployment's join
    /// policy is applied here, atomically with the account insert.
    ///
    /// An unclaimed deployment accepts anyone, because the first account is
    /// what claims it and there is nobody to issue an invite yet. Once claimed,
    /// joining is by invitation (see [`crate::store::invites`]), and the invite
    /// is spent in the same transaction that creates the account: a code that
    /// loses the race for its last remaining use leaves no orphan account
    /// behind, and an account that fails to insert never spends a code.
    ///
    /// The account insert is deliberately the transaction's first statement, so
    /// it takes the write lock up front rather than reading a snapshot it would
    /// later have to promote; the same reason [`Self::rotate_refresh`] claims
    /// write-first.
    pub async fn register_account(
        &self,
        username: &str,
        display_name: &str,
        password_hash: &str,
        invite_code: Option<&str>,
    ) -> Result<Account, RegisterError> {
        let id = UserId::generate();
        let now = now_ms();
        let mut tx = self.pool.begin().await?;

        let inserted = sqlx::query!(
            "INSERT INTO users (id, username, display_name, password_hash, created_at)
             VALUES (?, ?, ?, ?, ?)",
            id,
            username,
            display_name,
            password_hash,
            now
        )
        .execute(&mut *tx)
        .await;
        match inserted {
            Ok(_) => {}
            Err(sqlx::Error::Database(e)) if e.is_unique_violation() => {
                return Err(RegisterError::UsernameTaken);
            }
            Err(e) => return Err(RegisterError::Internal(e.into())),
        }

        // Read inside the transaction: a deployment claimed by a concurrent
        // first registration must not let this one in ungated.
        let claimed =
            sqlx::query_scalar!(r#"SELECT 1 AS "one!: i64" FROM roles WHERE is_everyone = 1"#)
                .fetch_optional(&mut *tx)
                .await?
                .is_some();

        // Read in the same transaction, for the same reason `claimed` is: a
        // policy change landing concurrently must not be missed here.
        let policy = super::space::read_join_policy(&mut *tx).await?;

        if claimed {
            // Dropping `tx` without committing rolls the account insert back, so
            // every early return below leaves the username free.
            let code = match (invite_code, policy) {
                (Some(code), _) => Some(code),
                // An open Space still accepts a code, so an invite that grants
                // a role keeps working; it just no longer demands one.
                (None, JoinPolicy::Open) => None,
                (None, JoinPolicy::Invite) => return Err(RegisterError::InviteRequired),
            };
            if let Some(code) = code {
                let Some(spent) = spend_invite(&mut tx, code, now).await? else {
                    return Err(RegisterError::InviteUnusable);
                };
                // Record it so this account cannot redeem the same code again for a second use; see SRV5.
                record_redemption(&mut tx, code, id, now).await?;
                if let Some(role_id) = spent {
                    sqlx::query!(
                        "INSERT OR IGNORE INTO member_roles (user_id, role_id) VALUES (?, ?)",
                        id,
                        role_id
                    )
                    .execute(&mut *tx)
                    .await?;
                }
            }
        }

        tx.commit().await?;
        Ok(Account {
            id,
            username: username.to_owned(),
        })
    }

    /// Inserts an account with no join policy applied at all.
    ///
    /// This is the bare primitive, for building a fixture or a scenario. It is
    /// NOT the registration path: a route that calls this reopens the hole
    /// where anyone could join a claimed deployment without an invite. Route
    /// handlers use [`Self::register_account`].
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
    ///
    /// The device insert is the transaction's first statement and is conditional
    /// on the account still being live, so it takes the write lock up front and a
    /// login that races an account deletion cannot mint a session for a
    /// tombstoned account: whichever of the two commits first wins, and a loser
    /// login gets [`OpenError::AccountGone`].
    pub async fn open_session(
        &self,
        user_id: UserId,
        device_name: &str,
    ) -> Result<IssuedTokens, OpenError> {
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
        let created = sqlx::query!(
            "INSERT INTO devices (id, user_id, name, created_at)
             SELECT ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM users WHERE id = ? AND deleted_at IS NULL)
               AND NOT EXISTS (SELECT 1 FROM space_removals WHERE user_id = ?)",
            device_id,
            user_id,
            device_name,
            now,
            user_id,
            user_id
        )
        .execute(&mut *tx)
        .await?
        .rows_affected();
        if created == 0 {
            // Decided in the same transaction, so it cannot disagree with the insert.
            return Err(if super::removals::removed(&mut tx, user_id).await? {
                OpenError::Removed
            } else {
                OpenError::AccountGone
            });
        }
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
    ///
    /// The token is spent atomically as the transaction's first statement.
    /// Making the first statement a write takes the write lock up front, so a
    /// concurrent rotation of the same token waits on the lock and then finds
    /// `used_at` already set, rather than both reading a NULL snapshot and one
    /// failing to promote its stale snapshot to a writer. A matched row means
    /// this call won the claim; no row means the token was unknown, revoked,
    /// expired, or already spent, which [`classify_failed_refresh`] sorts out.
    pub async fn rotate_refresh(&self, refresh_token: &str) -> anyhow::Result<RefreshOutcome> {
        let presented = hash_secret(refresh_token);
        let now = now_ms();
        let mut tx = self.pool.begin().await?;

        // Claim-first, so this transaction opens on a write; see the note on
        // this function.
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

        // Revocation marks the token revoked, which the claim guard excludes,
        // so this read is for the new tokens; the check is belt and braces.
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

        // Claimed atomically as the first statement, so a double redemption
        // cannot have both callers pass the `used_at` check.
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
/// gone, refresh tokens marked revoked, the session itself marked revoked, and
/// its device's push registration cleared.
///
/// The registration is cleared here, not left to the read-side liveness
/// filter in [`Store::push_targets`] alone, so a signed-out device stops being
/// a push target the instant it is revoked rather than on whatever cadence
/// the next read happens to run.
///
/// Both timestamp writes are guarded on the row still being live, so calling
/// this for an already-revoked session is a no-op on when it died rather than
/// a re-stamp. That matters wherever a caller revokes a set it did not filter
/// first, as [`Store::remove_device`] does.
pub(super) async fn revoke_session_rows(
    conn: &mut SqliteConnection,
    session_id: SessionId,
    now: i64,
) -> anyhow::Result<()> {
    sqlx::query!(
        "UPDATE devices
         SET platform = NULL, push_token_ref = NULL, voip_push_token_ref = NULL,
             push_public_key = NULL
         WHERE id = (SELECT device_id FROM sessions WHERE id = ?)",
        session_id
    )
    .execute(&mut *conn)
    .await?;
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
    // Guarded like the refresh_tokens update above; see this function's doc.
    sqlx::query!(
        "UPDATE sessions SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL",
        now,
        session_id
    )
    .execute(&mut *conn)
    .await?;
    Ok(())
}
