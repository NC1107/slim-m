// SPDX-License-Identifier: AGPL-3.0-only
//! The message write and read paths: send, edit, delete, list, and full-text
//! search, all over embedded SQLite.
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
//! Delete is soft: `deleted_at` is set, and every read here filters on it
//! except [`Store::message_including_deleted`], which a delete handler needs
//! so it can authorize against an already-gone row and stay idempotent.

use anyhow::Context;
use sqlx::SqliteExecutor;

use super::{Message, Store, now_ms};
use crate::ids::{ChannelId, MessageId, Seq, UserId};

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

/// Why a full-text search failed.
#[derive(Debug)]
pub enum SearchError {
    /// `q` is not valid FTS5 query syntax: an unterminated quote, a dangling
    /// operator, or an unknown column filter. FTS5 has no separate parse step
    /// sqlx can check ahead of time, so SQLite only reports this once the
    /// statement runs, and that is where this is caught rather than in
    /// up-front input validation.
    InvalidQuery,
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for SearchError {
    fn from(err: sqlx::Error) -> Self {
        if let sqlx::Error::Database(ref db_err) = err {
            let message = db_err.message();
            if message.contains("fts5")
                || message.contains("unterminated string")
                || message.contains("no such column")
            {
                return SearchError::InvalidQuery;
            }
        }
        SearchError::Internal(err.into())
    }
}

impl Store {
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

        // Read the name inside the same transaction the insert used, so the
        // echoed message cannot disagree with what a later fetch would return.
        let author_display_name = sqlx::query_scalar!(
            r#"SELECT display_name AS "display_name!: String"
               FROM users WHERE id = ? AND deleted_at IS NULL"#,
            author_id
        )
        .fetch_optional(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(Message {
            id,
            channel_id,
            author_id: Some(author_id),
            author_display_name,
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

    /// Soft-deletes a message. Returns whether this call performed the delete
    /// (`false` means it was already gone), so a retry after a dropped
    /// response stays idempotent and the caller can skip a redundant fan-out.
    ///
    /// Write-first: the `UPDATE` is the one statement, and its `WHERE` clause
    /// is both the claim and the idempotency check, so two racing deletes of
    /// the same message cannot both believe they were the one that deleted it.
    pub async fn delete_message(&self, id: MessageId) -> anyhow::Result<bool> {
        let now = now_ms();
        let affected = sqlx::query!(
            "UPDATE messages SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL",
            now,
            id
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        Ok(affected > 0)
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
            r#"SELECT m.id AS "id!: MessageId", m.channel_id AS "channel_id!: ChannelId",
                      m.author_id AS "author_id: UserId",
                      u.display_name AS "author_display_name?: String",
                      m.seq AS "seq!: Seq",
                      m.content AS "content!", m.created_at AS "created_at!", m.edited_at
               FROM messages m
               LEFT JOIN users u ON u.id = m.author_id AND u.deleted_at IS NULL
               WHERE m.channel_id = ? AND m.deleted_at IS NULL AND m.seq < ?
               ORDER BY m.seq DESC
               LIMIT ?"#,
            channel_id,
            before,
            limit
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }

    /// Full-text searches one channel's live messages, newest match first,
    /// keyset-paginated on `seq` exactly like [`Store::list_messages`].
    ///
    /// `query` reaches FTS5 close to as-is, so a caller may use its mini query
    /// language (`AND`/`OR`/`NOT`, `"phrase"`, a trailing `*` prefix). That is
    /// safe against leaking another channel: the index has exactly one column
    /// (`content`), so a query string has no other column to pivot to, and
    /// the channel and `deleted_at` restriction below are ordinary SQL
    /// predicates the query text can never reach - never part of the `MATCH`
    /// expression itself, so nothing in `query` can widen or redirect them.
    ///
    /// The FTS index is reindexed on every `UPDATE` to `messages`, including a
    /// soft delete, and that trigger does not itself drop a deleted row (only
    /// an encrypted one is excluded); this filters `deleted_at IS NULL`
    /// explicitly rather than relying on the index to have dropped it.
    pub async fn search_messages(
        &self,
        channel_id: ChannelId,
        query: &str,
        before_seq: Option<i64>,
        limit: i64,
    ) -> Result<Vec<Message>, SearchError> {
        // A join-free probe against the index first. The real query below
        // joins to `messages` and filters by channel, and when that join has
        // no candidate rows (an empty or brand-new channel), SQLite's planner
        // can prove the whole result is empty without ever calling into
        // FTS5's own query parser - which would let a malformed `query` slip
        // through as a silent empty result instead of failing. This probe has
        // nothing else to join against, so FTS5 must parse `query` to answer
        // it at all, and a bad query fails right here every time, regardless
        // of how many rows exist.
        sqlx::query_scalar!(
            r#"SELECT 1 AS "one!: i64" FROM messages_fts WHERE messages_fts MATCH ? LIMIT 1"#,
            query
        )
        .fetch_optional(&self.pool)
        .await?;

        let before = before_seq.unwrap_or(i64::MAX);
        let rows = sqlx::query_as!(
            Message,
            r#"SELECT m.id AS "id!: MessageId", m.channel_id AS "channel_id!: ChannelId",
                      m.author_id AS "author_id: UserId",
                      u.display_name AS "author_display_name?: String",
                      m.seq AS "seq!: Seq",
                      m.content AS "content!", m.created_at AS "created_at!", m.edited_at
               FROM messages_fts
               JOIN messages m ON m.rowid = messages_fts.rowid
               LEFT JOIN users u ON u.id = m.author_id AND u.deleted_at IS NULL
               WHERE messages_fts MATCH ?
                 AND m.channel_id = ?
                 AND m.deleted_at IS NULL
                 AND m.seq < ?
               ORDER BY m.seq DESC
               LIMIT ?"#,
            query,
            channel_id,
            before,
            limit
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }

    /// Fetches a live message by id, or `None` if it is missing or deleted.
    pub async fn message(&self, id: MessageId) -> anyhow::Result<Option<Message>> {
        fetch_message(&self.pool, id).await
    }

    /// Fetches a message by id whether or not it is deleted. A delete handler
    /// needs this rather than [`Store::message`] so it can authorize against
    /// an already-deleted row and tell "already gone" apart from "never
    /// existed here", which a `deleted_at`-filtered read cannot distinguish.
    pub async fn message_including_deleted(
        &self,
        id: MessageId,
    ) -> anyhow::Result<Option<Message>> {
        let message = sqlx::query_as!(
            Message,
            r#"SELECT m.id AS "id!: MessageId", m.channel_id AS "channel_id!: ChannelId",
                      m.author_id AS "author_id: UserId",
                      u.display_name AS "author_display_name?: String",
                      m.seq AS "seq!: Seq",
                      m.content AS "content!", m.created_at AS "created_at!", m.edited_at
               FROM messages m
               LEFT JOIN users u ON u.id = m.author_id AND u.deleted_at IS NULL
               WHERE m.id = ?"#,
            id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(message)
    }
}

/// Fetches one live message by id against any executor (pool or transaction).
async fn fetch_message<'e, E>(executor: E, id: MessageId) -> anyhow::Result<Option<Message>>
where
    E: SqliteExecutor<'e>,
{
    let message = sqlx::query_as!(
        Message,
        r#"SELECT m.id AS "id!: MessageId", m.channel_id AS "channel_id!: ChannelId",
                  m.author_id AS "author_id: UserId",
                  u.display_name AS "author_display_name?: String",
                  m.seq AS "seq!: Seq",
                  m.content AS "content!", m.created_at AS "created_at!", m.edited_at
           FROM messages m
           LEFT JOIN users u ON u.id = m.author_id AND u.deleted_at IS NULL
           WHERE m.id = ? AND m.deleted_at IS NULL"#,
        id
    )
    .fetch_optional(executor)
    .await?;
    Ok(message)
}
