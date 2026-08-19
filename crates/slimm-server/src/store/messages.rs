// SPDX-License-Identifier: AGPL-3.0-only
//! The message write and read paths: send, edit, delete and list, over
//! embedded SQLite. Full-text search is [`super::message_search`].
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

use super::attachments::{LinkError, link_attachments, release_message_attachments};
use super::message_ops::insert_message_op;
use super::{Message, Store, now_ms};
use crate::ids::{ChannelId, MessageId, Seq, UserId};

/// The outcome of a send, which is idempotent and so may be a retry.
#[derive(Debug, Clone)]
pub struct Sent {
    pub message: Message,
    /// False when this id was already stored, so the call was a retry of a send
    /// that already succeeded. Everything that must happen exactly once per
    /// message keys off this: fanning the message out again would duplicate it
    /// for every connected client, and pushing again would wake every idle
    /// recipient a second time for a message they were already told about.
    pub fresh: bool,
}

/// Why a message send failed.
#[derive(Debug)]
pub enum SendError {
    /// A message with this id already exists for a different channel or author.
    /// Idempotency is scoped so a colliding id never returns a foreign message.
    IdConflict,
    /// One of the referenced attachment ids was never uploaded, or was
    /// already swept as an orphan before this send reached it.
    AttachmentNotFound,
    /// `reply_to_id` named a message that does not exist, or that exists in a
    /// different channel from this send. A parent that exists in this
    /// channel but is already soft-deleted is still a valid target.
    InvalidReplyTarget,
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

impl From<LinkError> for SendError {
    fn from(err: LinkError) -> Self {
        match err {
            LinkError::NotFound => SendError::AttachmentNotFound,
            LinkError::Internal(e) => SendError::Internal(e),
        }
    }
}

/// What one message delete actually did, so the HTTP handler can tell a
/// caller and the fan-out hub apart from the filesystem cleanup that follows.
#[derive(Debug, Default, Clone)]
pub struct MessageDeletion {
    /// `false` means the message was already gone (a retry after a dropped
    /// response), the same idempotency contract the old boolean return had.
    pub deleted: bool,
    /// Whether the message was pinned at the moment this call deleted it,
    /// read before the soft-delete `UPDATE` fires `pinned_messages_on_delete`.
    /// A retry of an already-gone message is `false`, exactly like `deleted`.
    pub was_pinned: bool,
    /// Hex ids of attachments this delete left with no message referencing
    /// them. Their database rows are already gone; the caller still needs to
    /// delete the backing files, which is filesystem I/O kept outside the
    /// transaction that removed the rows.
    pub freed_attachments: Vec<String>,
    /// The op stream seq this delete allocated, absent when it deleted
    /// nothing. A 200 does not imply the cursor advanced.
    pub op_seq: Option<i64>,
}

/// What one edit actually did.
///
/// Three ways rather than two, because "no such message" and "the content was
/// already exactly this" need different answers from the caller: only a real
/// change publishes an event, and only a real change allocates an op seq. An
/// edit that changes nothing writing no op row is what keeps the op stream
/// dense, which is what makes a client's `n + 1` a fact rather than a guess.
#[derive(Debug, Clone)]
pub enum Edited {
    /// No live message with that id.
    Gone,
    /// The stored content was already byte-identical, so nothing was written:
    /// no op row, no seq, and `edited_at` is left where it was. The caller
    /// asked for a state and got it, so this is a 200 rather than an error.
    Unchanged(Message),
    Edited {
        message: Message,
        op_seq: i64,
    },
}

impl Store {
    /// Sends a message. Idempotent by `id` within its `(channel, author)` scope;
    /// the per-scope `seq` is allocated in the same transaction as the insert. A
    /// reused id that belongs to a different channel or author is rejected rather
    /// than returned, so the idempotency path cannot leak a foreign message.
    ///
    /// [`Sent::fresh`] is what separates a first send from a retry of one, so
    /// the caller can run the once-per-message side effects (fan-out, a push
    /// wake) only for a message that is genuinely new.
    ///
    /// `attachment_ids` (sha256 hashes of already-uploaded attachments) are
    /// linked inside this same transaction, so a message is never visible
    /// with only some of its attachments recorded: either every id resolves
    /// and the whole send commits, or none of it does.
    ///
    /// Uses [`Store::begin_write`] (`BEGIN IMMEDIATE`) rather than a deferred
    /// transaction, because this reads the id before it writes. A deferred
    /// transaction that has already taken a read snapshot cannot promote
    /// itself to a writer once another connection holds the write lock;
    /// SQLite answers that with SQLITE_BUSY straight away, ignoring
    /// `busy_timeout`, because waiting could deadlock. Taking the write lock
    /// up front makes concurrent sends queue instead.
    pub async fn send_message(
        &self,
        channel_id: ChannelId,
        author_id: UserId,
        id: MessageId,
        content: &str,
        attachment_ids: &[Vec<u8>],
        reply_to_id: Option<MessageId>,
    ) -> Result<Sent, SendError> {
        // Authorized before the write lock, never inside it; see `may_link`.
        for sha256 in attachment_ids {
            if !super::attachments::may_link(self, author_id, sha256).await? {
                return Err(SendError::AttachmentNotFound);
            }
        }

        // BEGIN IMMEDIATE, never deferred; see the note on this function.
        let mut tx = self.begin_write().await?;

        // Probes including a tombstoned row, not just a live one: the id column
        // is unique whether or not the message was deleted, so an idempotent
        // retry of a since-deleted message must match here and be returned as
        // the retry it is. Filtering deleted rows out let it fall through to an
        // INSERT that hit the unique id and mapped to a 500.
        if let Some(existing) = fetch_message_including_deleted(&mut *tx, id).await? {
            tx.commit().await?;
            if existing.channel_id == channel_id && existing.author_id == Some(author_id) {
                return Ok(Sent {
                    message: existing,
                    fresh: false,
                });
            }
            return Err(SendError::IdConflict);
        }

        // A reply's parent must already exist in this exact channel. The
        // column's bare `REFERENCES messages(id)` only proves the id exists
        // somewhere, never that it belongs here, so the channel is checked by
        // hand; a parent that is already soft-deleted still passes, since a
        // reply to something since removed is honest, not invalid.
        if let Some(parent_id) = reply_to_id {
            let parent_channel = sqlx::query_scalar!(
                r#"SELECT channel_id AS "channel_id!: ChannelId" FROM messages WHERE id = ?"#,
                parent_id
            )
            .fetch_optional(&mut *tx)
            .await?;
            if parent_channel != Some(channel_id) {
                tx.commit().await?;
                return Err(SendError::InvalidReplyTarget);
            }
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
            r#"INSERT INTO messages (id, channel_id, author_id, seq, content, created_at, reply_to_id)
               VALUES (?, ?, ?, ?, ?, ?, ?)"#,
            id,
            channel_id,
            author_id,
            seq,
            content,
            now,
            reply_to_id
        )
        .execute(&mut *tx)
        .await?;

        if !attachment_ids.is_empty() {
            link_attachments(&mut tx, id, attachment_ids).await?;
        }

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
                reply_to_id,
            },
            fresh: true,
        })
    }

    /// Edits a message's content. Returns `None` if it does not exist or is
    /// deleted. The FTS index is kept current by a database trigger.
    pub async fn edit_message(
        &self,
        id: MessageId,
        content: &str,
        actor_id: UserId,
    ) -> anyhow::Result<Edited> {
        let mut tx = self.begin_write().await?;
        let existing = sqlx::query!(
            r#"SELECT content AS "content!: String", channel_id AS "channel_id!: ChannelId"
               FROM messages WHERE id = ? AND deleted_at IS NULL"#,
            id
        )
        .fetch_optional(&mut *tx)
        .await?;
        let Some(existing) = existing else {
            tx.commit().await?;
            return Ok(Edited::Gone);
        };
        if existing.content == content {
            tx.commit().await?;
            let message = fetch_message(&self.pool, id)
                .await?
                .context("a message read inside the transaction vanished after it")?;
            return Ok(Edited::Unchanged(message));
        }

        let now = now_ms();
        // Capture the version being replaced before the row is overwritten; see migration 0050.
        sqlx::query!(
            "INSERT INTO message_edits (message_id, content, replaced_at) VALUES (?, ?, ?)",
            id,
            existing.content,
            now
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "UPDATE messages SET content = ?, edited_at = ? WHERE id = ?",
            content,
            now,
            id
        )
        .execute(&mut *tx)
        .await?;
        let op_seq = insert_message_op(
            &mut tx,
            existing.channel_id,
            id,
            "edit",
            Some(actor_id),
            now,
        )
        .await?;
        tx.commit().await?;

        let message = fetch_message(&self.pool, id)
            .await?
            .context("a message this transaction just edited vanished after it")?;
        Ok(Edited::Edited { message, op_seq })
    }

    /// Soft-deletes a message and releases its attachments. Returns whether
    /// this call performed the delete (`false` means it was already gone),
    /// so a retry after a dropped response stays idempotent and the caller
    /// can skip a redundant fan-out.
    ///
    /// The `UPDATE` is the transaction's first statement, and its `WHERE`
    /// clause is both the claim and the idempotency check, so two racing
    /// deletes of the same message cannot both believe they were the one
    /// that deleted it. Releasing the attachment links happens in the same
    /// transaction, so a message can never end up soft-deleted while still
    /// holding live attachment references.
    pub async fn delete_message(
        &self,
        id: MessageId,
        actor_id: UserId,
    ) -> anyhow::Result<MessageDeletion> {
        let mut tx = self.begin_write().await?;
        let now = now_ms();
        // Read before the trigger below removes it; see `MessageDeletion::was_pinned`.
        let was_pinned = sqlx::query_scalar!(
            r#"SELECT EXISTS(SELECT 1 FROM pinned_messages WHERE message_id = ?) AS "was_pinned!: bool""#,
            id
        )
        .fetch_one(&mut *tx)
        .await?;
        let channel_id = sqlx::query_scalar!(
            r#"UPDATE messages SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL
               RETURNING channel_id AS "channel_id!: ChannelId""#,
            now,
            id
        )
        .fetch_optional(&mut *tx)
        .await?;
        let Some(channel_id) = channel_id else {
            tx.commit().await?;
            return Ok(MessageDeletion::default());
        };

        let op_seq =
            insert_message_op(&mut tx, channel_id, id, "delete", Some(actor_id), now).await?;
        let freed_attachments = release_message_attachments(&mut tx, id).await?;
        tx.commit().await?;
        Ok(MessageDeletion {
            deleted: true,
            was_pinned,
            freed_attachments,
            op_seq: Some(op_seq),
        })
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
                      m.content AS "content!", m.created_at AS "created_at!", m.edited_at,
                      m.reply_to_id AS "reply_to_id: MessageId"
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
                      m.content AS "content!", m.created_at AS "created_at!", m.edited_at,
                      m.reply_to_id AS "reply_to_id: MessageId"
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
/// Like [`fetch_message`] but sees a deleted row too, for the send
/// idempotency probe: a retried id must match whether or not the first send's
/// message has since been deleted.
pub(super) async fn fetch_message_including_deleted<'e, E>(
    executor: E,
    id: MessageId,
) -> anyhow::Result<Option<Message>>
where
    E: SqliteExecutor<'e>,
{
    let message = sqlx::query_as!(
        Message,
        r#"SELECT m.id AS "id!: MessageId", m.channel_id AS "channel_id!: ChannelId",
                  m.author_id AS "author_id: UserId",
                  u.display_name AS "author_display_name?: String",
                  m.seq AS "seq!: Seq",
                  m.content AS "content!", m.created_at AS "created_at!", m.edited_at,
                  m.reply_to_id AS "reply_to_id: MessageId"
           FROM messages m
           LEFT JOIN users u ON u.id = m.author_id AND u.deleted_at IS NULL
           WHERE m.id = ?"#,
        id
    )
    .fetch_optional(executor)
    .await?;
    Ok(message)
}

pub(super) async fn fetch_message<'e, E>(
    executor: E,
    id: MessageId,
) -> anyhow::Result<Option<Message>>
where
    E: SqliteExecutor<'e>,
{
    let message = sqlx::query_as!(
        Message,
        r#"SELECT m.id AS "id!: MessageId", m.channel_id AS "channel_id!: ChannelId",
                  m.author_id AS "author_id: UserId",
                  u.display_name AS "author_display_name?: String",
                  m.seq AS "seq!: Seq",
                  m.content AS "content!", m.created_at AS "created_at!", m.edited_at,
                  m.reply_to_id AS "reply_to_id: MessageId"
           FROM messages m
           LEFT JOIN users u ON u.id = m.author_id AND u.deleted_at IS NULL
           WHERE m.id = ? AND m.deleted_at IS NULL"#,
        id
    )
    .fetch_optional(executor)
    .await?;
    Ok(message)
}
