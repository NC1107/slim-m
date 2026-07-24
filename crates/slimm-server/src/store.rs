// SPDX-License-Identifier: AGPL-3.0-only
//! The message write path and reads over embedded SQLite.
//!
//! Two invariants live here and are covered by tests:
//!
//! - Ordering. Every message takes the next value from a per-(channel, stream)
//!   counter, allocated inside the same transaction as the insert, so a
//!   channel's messages get a gap-free monotonic `seq` that is independent of
//!   any other channel or of the canvas stream.
//! - Idempotent send. A send is keyed by a client-generated [`MessageId`]; a
//!   retry with the same id returns the stored message and consumes no new
//!   sequence, so an at-least-once client never duplicates or reorders.
//!
//! This is inherent on [`Store`] for now; it lifts to a repository trait when a
//! second backend (Postgres) actually needs one.

use anyhow::Context;
use sqlx::{SqliteExecutor, SqlitePool};

use crate::ids::{ChannelId, MessageId, Seq, UserId};

mod bootstrap;
mod permissions;
mod read_state;
mod sessions;

pub use bootstrap::Bootstrap;
pub use sessions::{
    Account, IssuedTokens, OpenError, RefreshOutcome, RegisterError, SessionContext,
};

fn now_ms() -> i64 {
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

/// A user account.
#[derive(Debug, Clone)]
pub struct User {
    pub id: UserId,
    pub username: String,
    pub display_name: String,
    pub created_at: i64,
}

/// A message. `author_id` is null once the author's account is anonymized.
#[derive(Debug, Clone)]
pub struct Message {
    pub id: MessageId,
    pub channel_id: ChannelId,
    pub author_id: Option<UserId>,
    pub seq: Seq,
    pub content: String,
    pub created_at: i64,
    pub edited_at: Option<i64>,
}

/// How recently a spent refresh token may be replayed before it counts as reuse
/// rather than the honest client racing itself. See [`Store::rotate_refresh`].
const DEFAULT_REUSE_GRACE_MS: i64 = 10 * 1000;

/// Why a message send failed.
#[derive(Debug)]
pub enum SendError {
    /// A message with this id already exists for a different channel or author.
    /// Idempotency is scoped so a colliding id never returns a foreign message.
    IdConflict,
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for SendError {
    fn from(err: sqlx::Error) -> Self {
        SendError::Internal(err.into())
    }
}

impl From<anyhow::Error> for SendError {
    fn from(err: anyhow::Error) -> Self {
        SendError::Internal(err)
    }
}

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

    /// Creates a channel and seeds its message and canvas sequence counters.
    pub async fn create_channel(&self, name: &str, kind: &str) -> anyhow::Result<Channel> {
        let id = ChannelId::generate();
        let now = now_ms();
        let mut tx = self.pool.begin().await?;
        sqlx::query!(
            "INSERT INTO channels (id, name, kind, created_at) VALUES (?, ?, ?, ?)",
            id,
            name,
            kind,
            now
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "INSERT INTO channel_seq_counters (channel_id, stream, next_seq)
             VALUES (?, 'message', 1), (?, 'canvas', 1)",
            id,
            id
        )
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(Channel {
            id,
            name: name.to_owned(),
            kind: kind.to_owned(),
            created_at: now,
        })
    }

    /// Sends a message. Idempotent by `id` within its `(channel, author)` scope;
    /// the per-scope `seq` is allocated in the same transaction as the insert. A
    /// reused id that belongs to a different channel or author is rejected rather
    /// than returned, so the idempotency path cannot leak a foreign message.
    pub async fn send_message(
        &self,
        channel_id: ChannelId,
        author_id: UserId,
        id: MessageId,
        content: &str,
    ) -> Result<Message, SendError> {
        let mut tx = self.pool.begin().await?;

        if let Some(existing) = fetch_message(&mut *tx, id).await? {
            tx.commit().await?;
            if existing.channel_id == channel_id && existing.author_id == Some(author_id) {
                return Ok(existing);
            }
            return Err(SendError::IdConflict);
        }

        // RETURNING runs on the updated row, so `next_seq - 1` is the value this
        // message takes and `next_seq` is left pointing at the following one.
        let seq = sqlx::query_scalar!(
            r#"UPDATE channel_seq_counters SET next_seq = next_seq + 1
               WHERE channel_id = ? AND stream = 'message'
               RETURNING next_seq - 1 AS "seq!: i64""#,
            channel_id
        )
        .fetch_optional(&mut *tx)
        .await?
        .context("channel has no message sequence counter")?;

        let now = now_ms();
        sqlx::query!(
            r#"INSERT INTO messages (id, channel_id, author_id, seq, content, created_at)
               VALUES (?, ?, ?, ?, ?, ?)"#,
            id,
            channel_id,
            author_id,
            seq,
            content,
            now
        )
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(Message {
            id,
            channel_id,
            author_id: Some(author_id),
            seq: Seq(seq),
            content: content.to_owned(),
            created_at: now,
            edited_at: None,
        })
    }

    /// Edits a message's content. Returns `None` if it does not exist or is
    /// deleted. The FTS index is kept current by a database trigger.
    pub async fn edit_message(
        &self,
        id: MessageId,
        content: &str,
    ) -> anyhow::Result<Option<Message>> {
        let now = now_ms();
        let affected = sqlx::query!(
            "UPDATE messages SET content = ?, edited_at = ? WHERE id = ? AND deleted_at IS NULL",
            content,
            now,
            id
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        if affected == 0 {
            return Ok(None);
        }
        fetch_message(&self.pool, id).await
    }

    /// Lists a channel's live messages newest-first, using keyset pagination on
    /// `seq` (never OFFSET). Pass the smallest `seq` seen so far as `before_seq`
    /// to page backwards.
    pub async fn list_messages(
        &self,
        channel_id: ChannelId,
        before_seq: Option<i64>,
        limit: i64,
    ) -> anyhow::Result<Vec<Message>> {
        let before = before_seq.unwrap_or(i64::MAX);
        let rows = sqlx::query_as!(
            Message,
            r#"SELECT id AS "id!: MessageId", channel_id AS "channel_id!: ChannelId",
                      author_id AS "author_id: UserId", seq AS "seq!: Seq",
                      content AS "content!", created_at AS "created_at!", edited_at
               FROM messages
               WHERE channel_id = ? AND deleted_at IS NULL AND seq < ?
               ORDER BY seq DESC
               LIMIT ?"#,
            channel_id,
            before,
            limit
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }

    /// Fetches a live channel by id, or `None` if it is missing or deleted.
    pub async fn channel(&self, id: ChannelId) -> anyhow::Result<Option<Channel>> {
        let row = sqlx::query!(
            r#"SELECT id AS "id!: ChannelId", name AS "name!", kind AS "kind!",
                      created_at AS "created_at!"
               FROM channels WHERE id = ? AND deleted_at IS NULL"#,
            id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|r| Channel {
            id: r.id,
            name: r.name,
            kind: r.kind,
            created_at: r.created_at,
        }))
    }

    /// Fetches a live message by id, or `None` if it is missing or deleted.
    pub async fn message(&self, id: MessageId) -> anyhow::Result<Option<Message>> {
        fetch_message(&self.pool, id).await
    }
}

/// Fetches one live message by id against any executor (pool or transaction).
async fn fetch_message<'e, E>(executor: E, id: MessageId) -> anyhow::Result<Option<Message>>
where
    E: SqliteExecutor<'e>,
{
    let message = sqlx::query_as!(
        Message,
        r#"SELECT id AS "id!: MessageId", channel_id AS "channel_id!: ChannelId",
                  author_id AS "author_id: UserId", seq AS "seq!: Seq",
                  content AS "content!", created_at AS "created_at!", edited_at
           FROM messages WHERE id = ? AND deleted_at IS NULL"#,
        id
    )
    .fetch_optional(executor)
    .await?;
    Ok(message)
}
