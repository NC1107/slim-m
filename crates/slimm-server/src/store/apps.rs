// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! App surfaces: a message that launches an installed module's `app` extension
//! point, rendered inline as an interactive shared surface rather than as text.
//!
//! Creating one is creating a message, so [`Store::send_app_message`] mirrors
//! [`super::polls::Store::send_poll_message`] closely: the same idempotent-by-id
//! scoping and per-channel `seq` allocation in the same transaction as the
//! insert, just with the `(module_id, command)` this surface launches inserted
//! alongside. An app surface never outlives or moves between messages, so it is
//! keyed by `message_id` rather than a surrogate id of its own.
//!
//! The surface's live, shared state is not stored here: it is the module's own
//! output, recorded and broadcast through `code_runs` at block 0 exactly like a
//! run fenced code block (see [`super::code_runs`]), so slim keeps no notion of
//! what any app does.

use anyhow::Context;
use sqlx::QueryBuilder;

use super::{Message, Sent, Store, now_ms};
use crate::ids::{ChannelId, MessageId, Seq, UserId};

/// An app surface attached to a message: which installed module's command this
/// message launches. The rendered, shared state lives in `code_runs`, not here.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppSurface {
    pub module_id: String,
    pub command: String,
    pub created_by: Option<UserId>,
    pub created_at: i64,
}

/// Why creating an app-surface message failed.
#[derive(Debug)]
pub enum CreateAppSurfaceError {
    /// A message with this id already exists for a different channel or author.
    /// Mirrors `CreatePollError::IdConflict`: a reused id must never return a
    /// foreign message.
    IdConflict,
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for CreateAppSurfaceError {
    fn from(err: sqlx::Error) -> Self {
        CreateAppSurfaceError::Internal(err.into())
    }
}

impl From<anyhow::Error> for CreateAppSurfaceError {
    fn from(err: anyhow::Error) -> Self {
        CreateAppSurfaceError::Internal(err)
    }
}

impl Store {
    /// Sends a message that launches `module_id`'s `command`. Idempotent by
    /// `id` within its `(channel, author)` scope, exactly like
    /// [`super::messages::Store::send_message`].
    pub async fn send_app_message(
        &self,
        channel_id: ChannelId,
        author_id: UserId,
        id: MessageId,
        content: &str,
        module_id: &str,
        command: &str,
    ) -> Result<Sent, CreateAppSurfaceError> {
        let now = now_ms();
        // Reads the message before deciding what to write; see Store::begin_write.
        let mut tx = self.begin_write().await?;

        if let Some(existing) =
            super::message_reads::fetch_message_including_deleted(&mut *tx, id).await?
        {
            tx.commit().await?;
            if existing.channel_id == channel_id && existing.author_id == Some(author_id) {
                return Ok(Sent {
                    message: existing,
                    fresh: false,
                });
            }
            return Err(CreateAppSurfaceError::IdConflict);
        }

        let seq = sqlx::query_scalar!(
            r#"UPDATE channel_seq_counters SET next_seq = next_seq + 1
               WHERE channel_id = ? AND stream = 'message'
               RETURNING next_seq - 1 AS "seq!: i64""#,
            channel_id
        )
        .fetch_optional(&mut *tx)
        .await?
        .context("channel has no message sequence counter")?;

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

        sqlx::query!(
            r#"INSERT INTO app_surfaces (message_id, channel_id, module_id, command, created_by, created_at)
               VALUES (?, ?, ?, ?, ?, ?)"#,
            id,
            channel_id,
            module_id,
            command,
            author_id,
            now
        )
        .execute(&mut *tx)
        .await?;

        let author_display_name = sqlx::query_scalar!(
            r#"SELECT display_name AS "display_name!: String"
               FROM users WHERE id = ? AND deleted_at IS NULL"#,
            author_id
        )
        .fetch_optional(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(Sent {
            message: Message {
                id,
                channel_id,
                author_id: Some(author_id),
                author_display_name,
                seq: Seq(seq),
                content: content.to_owned(),
                created_at: now,
                edited_at: None,
                reply_to_id: None,
            },
            fresh: true,
        })
    }

    /// A single message's app surface, or `None` if it carries none.
    pub async fn app_surface_for_message(
        &self,
        message_id: MessageId,
    ) -> anyhow::Result<Option<AppSurface>> {
        Ok(self
            .app_surfaces_for_messages(&[message_id])
            .await?
            .into_iter()
            .next()
            .map(|(_, surface)| surface))
    }

    /// App surfaces for a page of messages in one query, the same batch-enrich
    /// shape reactions and code runs use - a query per row would be a query per
    /// message. Only messages that actually carry a surface appear.
    pub async fn app_surfaces_for_messages(
        &self,
        message_ids: &[MessageId],
    ) -> anyhow::Result<Vec<(MessageId, AppSurface)>> {
        if message_ids.is_empty() {
            return Ok(Vec::new());
        }
        use sqlx::Row;

        let mut builder = QueryBuilder::new(
            "SELECT message_id, module_id, command, created_by, created_at \
             FROM app_surfaces WHERE message_id IN (",
        );
        let mut separated = builder.separated(", ");
        for id in message_ids {
            separated.push_bind(*id);
        }
        builder.push(")");
        let rows = builder.build().fetch_all(&self.pool).await?;

        rows.into_iter()
            .map(|row| {
                let message_id: MessageId = row.try_get("message_id")?;
                Ok((
                    message_id,
                    AppSurface {
                        module_id: row.try_get("module_id")?,
                        command: row.try_get("command")?,
                        created_by: row.try_get("created_by")?,
                        created_at: row.try_get("created_at")?,
                    },
                ))
            })
            .collect()
    }
}
