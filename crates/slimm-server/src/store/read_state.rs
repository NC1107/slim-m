// SPDX-License-Identifier: AGPL-3.0-only
//! Read state and the catch-up read path.
//!
//! Read state is a per-(user, channel) monotonic `last_read_seq`. Unread is not
//! stored; it is derived on demand as a range count of live messages past that
//! seq, which the `(channel_id, seq)` index answers cheaply. Catch-up returns
//! the messages after a client's per-scope cursor in ascending order, which the
//! bundled sync endpoint calls once per requested scope.

use super::{Message, Store, now_ms};
use crate::ids::{ChannelId, MessageId, Seq, UserId};

impl Store {
    /// Advances a user's last-read marker in a channel. Monotonic: a lower seq
    /// never moves it backwards, so out-of-order marks are safe.
    pub async fn mark_read(
        &self,
        user_id: UserId,
        channel_id: ChannelId,
        seq: i64,
    ) -> anyhow::Result<()> {
        let now = now_ms();
        sqlx::query!(
            "INSERT INTO read_states (user_id, channel_id, last_read_seq, updated_at)
             VALUES (?, ?, ?, ?)
             ON CONFLICT(user_id, channel_id) DO UPDATE SET
                 last_read_seq = MAX(last_read_seq, excluded.last_read_seq),
                 updated_at = excluded.updated_at",
            user_id,
            channel_id,
            seq,
            now
        )
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// A user's last-read seq in a channel, or 0 if they have never read it.
    pub async fn last_read_seq(
        &self,
        user_id: UserId,
        channel_id: ChannelId,
    ) -> anyhow::Result<i64> {
        let seq = sqlx::query_scalar!(
            r#"SELECT last_read_seq AS "seq!: i64"
               FROM read_states WHERE user_id = ? AND channel_id = ?"#,
            user_id,
            channel_id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(seq.unwrap_or(0))
    }

    /// The count of live messages a user has not read in a channel.
    pub async fn unread_count(
        &self,
        user_id: UserId,
        channel_id: ChannelId,
    ) -> anyhow::Result<i64> {
        let count = sqlx::query_scalar!(
            r#"SELECT COUNT(*) AS "count!: i64"
               FROM messages
               WHERE channel_id = ? AND deleted_at IS NULL
                 AND seq > COALESCE(
                     (SELECT last_read_seq FROM read_states
                      WHERE user_id = ? AND channel_id = ?),
                     0)"#,
            channel_id,
            user_id,
            channel_id
        )
        .fetch_one(&self.pool)
        .await?;
        Ok(count)
    }

    /// The highest message seq allocated in a channel, or 0 if none. Used to size
    /// the gap a catch-up must cover without scanning the message rows.
    pub async fn latest_message_seq(&self, channel_id: ChannelId) -> anyhow::Result<i64> {
        let seq = sqlx::query_scalar!(
            r#"SELECT (next_seq - 1) AS "seq!: i64"
               FROM channel_seq_counters
               WHERE channel_id = ? AND stream = 'message'"#,
            channel_id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(seq.unwrap_or(0))
    }

    /// Live messages after `after_seq`, oldest first, for catch-up. The caller
    /// passes `limit + 1` to detect whether more remain.
    pub async fn messages_since(
        &self,
        channel_id: ChannelId,
        after_seq: i64,
        limit: i64,
    ) -> anyhow::Result<Vec<Message>> {
        let rows = sqlx::query_as!(
            Message,
            r#"SELECT m.id AS "id!: MessageId", m.channel_id AS "channel_id!: ChannelId",
                      m.author_id AS "author_id: UserId",
                      u.display_name AS "author_display_name?: String",
                      m.seq AS "seq!: Seq",
                      m.content AS "content!", m.created_at AS "created_at!", m.edited_at
               FROM messages m
               LEFT JOIN users u ON u.id = m.author_id AND u.deleted_at IS NULL
               WHERE m.channel_id = ? AND m.deleted_at IS NULL AND m.seq > ?
               ORDER BY m.seq ASC
               LIMIT ?"#,
            channel_id,
            after_seq,
            limit
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }
}
