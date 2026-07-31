// SPDX-License-Identifier: AGPL-3.0-only
//! Full-text search over messages, split out of [`super::messages`] when that
//! file crossed the 500-line hard ceiling.
//!
//! Its own file rather than a section of that one because it is the only
//! read here with a failure mode of its own: FTS5 has no separate parse step
//! sqlx can check ahead of time, so a malformed query is reported by SQLite
//! only once the statement runs, and telling that apart from a genuinely
//! empty result is what [`SearchError`] exists for.

use super::{Message, Store};
use crate::ids::{ChannelId, MessageId, Seq, UserId};

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
    ///
    /// A malformed `query` must fail rather than come back empty, which is why
    /// the body opens with a join-free probe against the index. The real query
    /// joins to `messages` and filters by channel, and when that join has no
    /// candidate rows (an empty or brand-new channel) SQLite's planner can
    /// prove the whole result is empty without ever calling into FTS5's query
    /// parser - so a bad query would slip through as a silent empty result.
    /// The probe has nothing to join against, so FTS5 must parse `query` to
    /// answer it at all, and a bad one fails there every time regardless of
    /// how many rows exist.
    pub async fn search_messages(
        &self,
        channel_id: ChannelId,
        query: &str,
        before_seq: Option<i64>,
        limit: i64,
    ) -> Result<Vec<Message>, SearchError> {
        // Join-free probe so FTS5 must parse `query`; not dead work, see the doc above.
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
               JOIN messages m ON m.fts_rowid = messages_fts.rowid
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
}
