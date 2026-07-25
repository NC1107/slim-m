// SPDX-License-Identifier: AGPL-3.0-only
//! Reactions: a per-(message, user, emoji) set.
//!
//! The primary key is the whole triple, so reacting twice with the same emoji
//! is naturally idempotent rather than something the handler has to check for.
//! That matters because a double tap on a slow connection is the normal case,
//! not an edge case.
//!
//! Summaries are read for a whole page of messages in one query. Doing it per
//! message would be a query per row in a fifty-message page, which is the
//! shape of problem that only shows up once a channel has real traffic.

use sqlx::QueryBuilder;

use super::Store;
use crate::ids::{MessageId, UserId};

/// Longest an emoji may be. Grapheme clusters with modifiers and zero-width
/// joiners run long (a family emoji is well over 20 bytes), so this is
/// generous, but bounded: the column is not a place to stash arbitrary text.
pub const MAX_EMOJI_BYTES: usize = 64;

/// How many distinct emoji one message may carry, across all users. Without a
/// cap a single message is an unbounded write target.
pub const MAX_DISTINCT_EMOJI_PER_MESSAGE: i64 = 40;

/// One emoji on one message, with who used it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReactionSummary {
    pub emoji: String,
    pub count: i64,
    /// Whether the user who asked reacted with this emoji. The client needs it
    /// to render the toggled state without a second request.
    pub reacted: bool,
}

/// Why adding a reaction failed.
#[derive(Debug)]
pub enum ReactError {
    /// The message does not exist, or is deleted.
    UnknownMessage,
    /// The emoji is empty or longer than [`MAX_EMOJI_BYTES`].
    InvalidEmoji,
    /// This message already carries [`MAX_DISTINCT_EMOJI_PER_MESSAGE`] distinct
    /// emoji and this would be another one.
    TooManyDistinctEmoji,
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for ReactError {
    fn from(err: sqlx::Error) -> Self {
        ReactError::Internal(err.into())
    }
}

impl Store {
    /// Adds a reaction. Idempotent: reacting again with the same emoji leaves
    /// exactly one row and is not an error.
    pub async fn add_reaction(
        &self,
        message_id: MessageId,
        user_id: UserId,
        emoji: &str,
    ) -> Result<(), ReactError> {
        if emoji.is_empty() || emoji.len() > MAX_EMOJI_BYTES {
            return Err(ReactError::InvalidEmoji);
        }

        let now = super::now_ms();
        let mut tx = self.pool.begin().await?;

        // Existence is checked inside the transaction rather than before it,
        // so a message deleted concurrently cannot slip a reaction in behind
        // the check.
        let exists = sqlx::query_scalar!(
            r#"SELECT 1 AS "one!: i64" FROM messages WHERE id = ? AND deleted_at IS NULL"#,
            message_id
        )
        .fetch_optional(&mut *tx)
        .await?
        .is_some();
        if !exists {
            return Err(ReactError::UnknownMessage);
        }

        // Counting only when the emoji is new to this message keeps a busy
        // message with few distinct emoji cheap, and bounds the one case that
        // actually grows the row count.
        let is_new = sqlx::query_scalar!(
            r#"SELECT 1 AS "one!: i64" FROM reactions WHERE message_id = ? AND emoji = ? LIMIT 1"#,
            message_id,
            emoji
        )
        .fetch_optional(&mut *tx)
        .await?
        .is_none();
        if is_new {
            let distinct = sqlx::query_scalar!(
                r#"SELECT COUNT(DISTINCT emoji) AS "n!: i64" FROM reactions WHERE message_id = ?"#,
                message_id
            )
            .fetch_one(&mut *tx)
            .await?;
            if distinct >= MAX_DISTINCT_EMOJI_PER_MESSAGE {
                return Err(ReactError::TooManyDistinctEmoji);
            }
        }

        sqlx::query!(
            "INSERT OR IGNORE INTO reactions (message_id, user_id, emoji, created_at)
             VALUES (?, ?, ?, ?)",
            message_id,
            user_id,
            emoji,
            now
        )
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(())
    }

    /// Removes a reaction. Removing one that was never there is not an error:
    /// the caller's intent is "this emoji of mine is gone", and it is.
    pub async fn remove_reaction(
        &self,
        message_id: MessageId,
        user_id: UserId,
        emoji: &str,
    ) -> anyhow::Result<()> {
        sqlx::query!(
            "DELETE FROM reactions WHERE message_id = ? AND user_id = ? AND emoji = ?",
            message_id,
            user_id,
            emoji
        )
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Summaries for one message, ordered by first use so the row does not
    /// reshuffle under the reader as counts change.
    pub async fn reactions_for_message(
        &self,
        message_id: MessageId,
        viewer: UserId,
    ) -> anyhow::Result<Vec<ReactionSummary>> {
        Ok(self
            .reactions_for_messages(&[message_id], viewer)
            .await?
            .into_iter()
            .next()
            .map(|(_, summaries)| summaries)
            .unwrap_or_default())
    }

    /// Summaries for a page of messages, in one query.
    ///
    /// Returns only messages that actually have reactions, so the caller must
    /// treat a missing id as "no reactions" rather than expecting one entry per
    /// input.
    pub async fn reactions_for_messages(
        &self,
        message_ids: &[MessageId],
        viewer: UserId,
    ) -> anyhow::Result<Vec<(MessageId, Vec<ReactionSummary>)>> {
        if message_ids.is_empty() {
            return Ok(Vec::new());
        }

        // Built rather than a fixed `query!` because the id list is variable
        // length and SQLite has no array binding.
        let mut builder = QueryBuilder::new(
            "SELECT message_id, emoji, COUNT(*) AS n, \
             MAX(CASE WHEN user_id = ",
        );
        builder.push_bind(viewer);
        builder.push(
            " THEN 1 ELSE 0 END) AS reacted, MIN(created_at) AS first_at \
             FROM reactions WHERE message_id IN (",
        );
        let mut separated = builder.separated(", ");
        for id in message_ids {
            separated.push_bind(*id);
        }
        builder.push(") GROUP BY message_id, emoji ORDER BY first_at ASC");

        let rows = builder.build().fetch_all(&self.pool).await?;

        use sqlx::Row;
        let mut grouped: Vec<(MessageId, Vec<ReactionSummary>)> = Vec::new();
        for row in rows {
            let message_id: MessageId = row.try_get("message_id")?;
            let summary = ReactionSummary {
                emoji: row.try_get("emoji")?,
                count: row.try_get("n")?,
                reacted: row.try_get::<i64, _>("reacted")? == 1,
            };
            match grouped.iter_mut().find(|(id, _)| *id == message_id) {
                Some((_, list)) => list.push(summary),
                None => grouped.push((message_id, vec![summary])),
            }
        }
        Ok(grouped)
    }
}
