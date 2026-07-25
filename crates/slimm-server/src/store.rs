// SPDX-License-Identifier: AGPL-3.0-only
//! The persistence layer over one embedded SQLite database: the [`Store`]
//! handle itself, the domain types shared across every feature submodule, and
//! the handful of methods (account creation, liveness, live user ids) that do
//! not belong to any single feature area.
//!
//! Everything else is split by feature, mirroring the HTTP surface: messages
//! (send, edit, delete, list, search) in [`messages`], channel CRUD in
//! [`channels`], user profiles and the member list in [`users`], reactions in
//! [`reactions`], and so on. This is inherent on [`Store`] for now; it lifts
//! to a repository trait when a second backend (Postgres) actually needs one.

use sqlx::SqlitePool;

use crate::ids::{ChannelId, MessageId, Seq, UserId};

mod bootstrap;
mod channels;
mod invites;
mod messages;
mod permissions;
mod push;
mod reactions;
mod read_state;
mod recovery;
mod roles;
mod safety;
mod sessions;
mod users;

pub use bootstrap::Bootstrap;
pub use channels::DeleteChannelError;
pub use invites::{Invite, RedeemError};
pub use messages::{SearchError, SendError};
pub use push::{PushError, PushTarget};
pub use reactions::{MAX_EMOJI_BYTES, ReactError, ReactionSummary};
pub use recovery::{ConsumeResetError, IssueResetError};
pub use roles::{Role, RoleGuardError};
pub use safety::{Device, Report, ReportError, ReportSubject};
pub use sessions::{
    Account, DeleteAccountError, IssuedTokens, OpenError, RefreshOutcome, RegisterError,
    SessionContext,
};

/// Unix milliseconds, `pub(crate)` so the push trigger path (outside this
/// module) can compare a lifecycle report's age against the same clock
/// everything here is stamped with.
pub(crate) fn now_ms() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// A channel (a text or voice room).
#[derive(Debug, Clone)]
pub struct Channel {
    pub id: ChannelId,
    pub name: String,
    pub kind: String,
    pub created_at: i64,
}

/// A user account's public profile. Deliberately narrow: id, username,
/// display name, and creation time only. Nothing from the auth tables
/// (password hash, sessions, tokens) has a type that could even be confused
/// with this one.
#[derive(Debug, Clone)]
pub struct User {
    pub id: UserId,
    pub username: String,
    pub display_name: String,
    pub created_at: i64,
}

/// A message. `author_id` is null once the author's account is anonymized.
///
/// The author's display name rides along with the message rather than being
/// looked up per author by the client, which would be a request per distinct
/// sender in a channel. It is null for the same reason `author_id` is: the
/// account was anonymized, and there is no name left to show.
#[derive(Debug, Clone)]
pub struct Message {
    pub id: MessageId,
    pub channel_id: ChannelId,
    pub author_id: Option<UserId>,
    pub author_display_name: Option<String>,
    pub seq: Seq,
    pub content: String,
    pub created_at: i64,
    pub edited_at: Option<i64>,
}

/// How recently a spent refresh token may be replayed before it counts as reuse
/// rather than the honest client racing itself. See [`Store::rotate_refresh`].
const DEFAULT_REUSE_GRACE_MS: i64 = 10 * 1000;

/// The persistence layer over one embedded SQLite database.
#[derive(Clone)]
pub struct Store {
    pool: SqlitePool,
    reuse_grace_ms: i64,
}

impl Store {
    pub fn new(pool: SqlitePool) -> Self {
        Self {
            pool,
            reuse_grace_ms: DEFAULT_REUSE_GRACE_MS,
        }
    }

    /// Builds a store with an explicit refresh-reuse grace window. Mainly for
    /// tests that need to exercise the out-of-grace reuse path deterministically.
    pub fn with_reuse_grace_ms(pool: SqlitePool, reuse_grace_ms: i64) -> Self {
        Self {
            pool,
            reuse_grace_ms,
        }
    }

    /// Confirms the database answers a trivial query. Backs the liveness probe.
    pub async fn ping(&self) -> anyhow::Result<()> {
        sqlx::query("SELECT 1").execute(&self.pool).await?;
        Ok(())
    }

    /// Creates a passwordless user. Used by tests and internal fixtures; the
    /// authenticated registration path is [`Store::create_account`].
    pub async fn create_user(&self, username: &str, display_name: &str) -> anyhow::Result<User> {
        let id = UserId::generate();
        let now = now_ms();
        sqlx::query!(
            "INSERT INTO users (id, username, display_name, created_at) VALUES (?, ?, ?, ?)",
            id,
            username,
            display_name,
            now
        )
        .execute(&self.pool)
        .await?;
        Ok(User {
            id,
            username: username.to_owned(),
            display_name: display_name.to_owned(),
            created_at: now,
        })
    }

    /// Every live user's id. Used to compute who can view a channel for push
    /// fan-out; small self-hosted deployments make an O(users) scan cheap
    /// enough that a dedicated membership table is not worth carrying yet.
    pub async fn live_user_ids(&self) -> anyhow::Result<Vec<UserId>> {
        let rows =
            sqlx::query!(r#"SELECT id AS "id!: UserId" FROM users WHERE deleted_at IS NULL"#)
                .fetch_all(&self.pool)
                .await?;
        Ok(rows.into_iter().map(|r| r.id).collect())
    }
}
