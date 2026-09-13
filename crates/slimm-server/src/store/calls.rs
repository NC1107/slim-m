// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! What happened to a DM call, recorded so a call nobody answered leaves a
//! trace.
//!
//! Every part of ringing before this was ephemeral - the ring lives in memory,
//! `sweeps::sweep_stale_call_rings` tears it down after the timeout, and
//! nothing was written anywhere - so a missed call was invisible to the person
//! who missed it, which is exactly the case that needed to be visible.
//!
//! Carried by a message rather than a log of its own, because a call is an
//! event in a conversation and the transcript is where a person looks for what
//! happened in one. Riding a message also means this inherits ordering,
//! pagination, sync, unread state and notification without any of them
//! learning about calls. [`Store::record_call`] therefore mirrors
//! [`super::app_surfaces::Store::send_app_message`]: the same per-channel `seq`
//! allocation and side-table insert in one transaction.
//!
//! Unlike every other message writer here, the author is the **caller** even
//! for a call the caller missed being answered. Someone has to own the row,
//! there is no system author in this schema, and attributing "you called and
//! nobody picked up" to the person who called is the reading that matches what
//! happened.

use anyhow::Context;
use sqlx::QueryBuilder;

use super::{Message, Sent, Store, now_ms};
use crate::ids::{ChannelId, MessageId, Seq, UserId};

/// How a DM call ended, and how long it lasted if it happened at all.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CallRecord {
    pub caller_id: Option<UserId>,
    pub outcome: String,
    /// Null for every outcome but `answered`: nothing lasted any time when
    /// nobody picked up.
    pub duration_ms: Option<i64>,
    pub created_at: i64,
}

impl Store {
    /// Writes the message that carries a finished call, and the record itself.
    ///
    /// The message content is deliberately empty. What to say about a call is
    /// a rendering decision that depends on which side is reading it - "missed
    /// call" and "you called, no answer" are the same row - so the text is the
    /// client's to choose and nothing here freezes one reading into storage.
    ///
    /// Not idempotent by caller-supplied id, unlike the other message writers:
    /// nothing outside the server ever asks for one of these, and every call
    /// site is a ring reaching exactly one terminal state once.
    pub async fn record_call(
        &self,
        channel_id: ChannelId,
        caller_id: UserId,
        outcome: &str,
        duration_ms: Option<i64>,
    ) -> anyhow::Result<Sent> {
        let now = now_ms();
        let id = MessageId::generate();
        let mut tx = self.begin_write().await?;

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
               VALUES (?, ?, ?, ?, '', ?)"#,
            id,
            channel_id,
            caller_id,
            seq,
            now
        )
        .execute(&mut *tx)
        .await?;

        sqlx::query!(
            r#"INSERT INTO call_records
                   (message_id, channel_id, caller_id, outcome, duration_ms, created_at)
               VALUES (?, ?, ?, ?, ?, ?)"#,
            id,
            channel_id,
            caller_id,
            outcome,
            duration_ms,
            now
        )
        .execute(&mut *tx)
        .await?;

        let author_display_name = sqlx::query_scalar!(
            r#"SELECT display_name AS "display_name!: String"
               FROM users WHERE id = ? AND deleted_at IS NULL"#,
            caller_id
        )
        .fetch_optional(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(Sent {
            message: Message {
                id,
                channel_id,
                author_id: Some(caller_id),
                author_display_name,
                seq: Seq(seq),
                content: String::new(),
                created_at: now,
                edited_at: None,
                reply_to_id: None,
            },
            fresh: true,
        })
    }

    /// A single message's call record, or `None` if it carries none. The
    /// live `message.created` frame uses this: a call message whose record
    /// has not arrived renders as the empty string it stores.
    pub async fn call_for_message(
        &self,
        message_id: MessageId,
    ) -> anyhow::Result<Option<CallRecord>> {
        Ok(self
            .calls_for_messages(&[message_id])
            .await?
            .into_iter()
            .next()
            .map(|(_, record)| record))
    }

    /// Call records for a page of messages in one query, the same batch-enrich
    /// shape reactions, code runs and app surfaces use. Only messages that
    /// actually carry a call appear.
    pub async fn calls_for_messages(
        &self,
        message_ids: &[MessageId],
    ) -> anyhow::Result<Vec<(MessageId, CallRecord)>> {
        if message_ids.is_empty() {
            return Ok(Vec::new());
        }
        use sqlx::Row;

        let mut builder = QueryBuilder::new(
            "SELECT message_id, caller_id, outcome, duration_ms, created_at \
             FROM call_records WHERE message_id IN (",
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
                    CallRecord {
                        caller_id: row.try_get("caller_id")?,
                        outcome: row.try_get("outcome")?,
                        duration_ms: row.try_get("duration_ms")?,
                        created_at: row.try_get("created_at")?,
                    },
                ))
            })
            .collect()
    }
}
