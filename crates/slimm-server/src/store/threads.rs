// SPDX-License-Identifier: AGPL-3.0-only
//! Threads: a hidden channel opened from one message, per
//! docs/decisions/0005-threads.md's recommendation. A thread is not its own
//! kind of thing - it is an ordinary row in `channels` with
//! `parent_message_id` set, so every other feature (send, edit, keyset
//! pagination, full-text search, bundled sync, push fan-out, the WebSocket
//! fan-out filter) keeps working unchanged, the same leverage modelling a DM
//! as a channel already bought this codebase once.
//!
//! What is different from a DM: a thread's permissions are never evaluated
//! against itself. [`Store::permission_channel`] (`permissions.rs`) resolves
//! them from the channel its parent message lives in, live, on every check -
//! there is no synthesized overwrite and no copy of the parent's bits to go
//! stale.

use super::{Channel, Store, now_ms};
use crate::ids::{ChannelId, MessageId};

/// Why opening a thread failed.
#[derive(Debug)]
pub enum OpenThreadError {
    /// The named message does not exist in this channel, or has been deleted.
    UnknownMessage,
    /// The named message is itself inside a thread. Refused rather than
    /// nested: [`Store::permission_channel`] resolves one hop, from a thread
    /// to the channel its parent message lives in, and stops there - a
    /// second thread layered on top would resolve to the first thread's own
    /// (empty) overwrite bucket instead of the real channel's, silently
    /// dropping whatever deny the real channel had set.
    NestedThread,
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for OpenThreadError {
    fn from(err: sqlx::Error) -> Self {
        OpenThreadError::Internal(err.into())
    }
}

impl From<anyhow::Error> for OpenThreadError {
    fn from(err: anyhow::Error) -> Self {
        OpenThreadError::Internal(err)
    }
}

impl Store {
    /// Opens the thread hanging off `message_id`, creating it on first use.
    ///
    /// Idempotent and race-safe the way [`Store::open_dm`] is: this reads
    /// whether the message already has a thread before deciding whether to
    /// create one, so it uses [`Store::begin_write`] (`BEGIN IMMEDIATE`)
    /// rather than a plain transaction, and two callers racing the same
    /// message converge on one channel rather than two.
    pub async fn open_thread(
        &self,
        channel_id: ChannelId,
        message_id: MessageId,
    ) -> Result<Channel, OpenThreadError> {
        let mut tx = self.begin_write().await?;

        let row = sqlx::query!(
            r#"SELECT c.parent_message_id AS "parent_message_id: MessageId"
               FROM messages m JOIN channels c ON c.id = m.channel_id
               WHERE m.id = ? AND m.channel_id = ? AND m.deleted_at IS NULL"#,
            message_id,
            channel_id
        )
        .fetch_optional(&mut *tx)
        .await?;
        let Some(row) = row else {
            return Err(OpenThreadError::UnknownMessage);
        };
        if row.parent_message_id.is_some() {
            return Err(OpenThreadError::NestedThread);
        }

        if let Some(existing) = sqlx::query_scalar!(
            r#"SELECT id AS "id!: ChannelId" FROM channels
               WHERE parent_message_id = ? AND deleted_at IS NULL"#,
            message_id
        )
        .fetch_optional(&mut *tx)
        .await?
        {
            tx.commit().await?;
            return self.channel(existing).await?.ok_or_else(|| {
                anyhow::anyhow!("thread channel row exists but is not live").into()
            });
        }

        let id = ChannelId::generate();
        let now = now_ms();
        // A thread has no name of its own; a client titles the panel "Thread".
        sqlx::query!(
            "INSERT INTO channels (id, name, kind, parent_message_id, created_at)
             VALUES (?, '', 'text', ?, ?)",
            id,
            message_id,
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
            name: String::new(),
            kind: "text".to_owned(),
            topic: None,
            // Never read: a thread is excluded from every position-ordered query.
            position: 0,
            parent_message_id: Some(message_id),
            created_at: now,
        })
    }

    /// Which of `message_ids` already has a live thread, and its channel id -
    /// the batch lookup [`super::super::http::message_enrich`] attaches to
    /// each message the same way it attaches reactions and attachments, so a
    /// client that was never online for the thread's creation still learns
    /// it exists the next time it lists, searches, or syncs the parent
    /// channel, rather than depending on having seen a live event for it.
    pub async fn threads_for_messages(
        &self,
        message_ids: &[MessageId],
    ) -> anyhow::Result<Vec<(MessageId, ChannelId)>> {
        if message_ids.is_empty() {
            return Ok(Vec::new());
        }
        let mut builder = sqlx::QueryBuilder::new(
            "SELECT parent_message_id, id FROM channels \
             WHERE deleted_at IS NULL AND parent_message_id IN (",
        );
        let mut separated = builder.separated(", ");
        for id in message_ids {
            separated.push_bind(*id);
        }
        builder.push(")");
        let rows = builder.build().fetch_all(&self.pool).await?;

        use sqlx::Row;
        rows.into_iter()
            .map(|row| {
                let parent: MessageId = row.try_get("parent_message_id")?;
                let id: ChannelId = row.try_get("id")?;
                Ok((parent, id))
            })
            .collect()
    }
}
