// SPDX-License-Identifier: AGPL-3.0-only
//! Deleting several messages as one act.
//!
//! A raid is the case this exists for: with only [`Store::delete_message`], a
//! moderator spends one request and one confirmation per spam message while it
//! is still arriving.
//!
//! Every side effect of the single delete is reproduced here, because a bulk
//! path that quietly does less than the single one is worse than no bulk path
//! at all. That is the soft delete guarded by `deleted_at IS NULL`, one op per
//! message actually deleted, and the attachment release - plus the triggers
//! 0024 hangs off `messages`, which fire per row whatever shape the statement
//! has, so batching the `UPDATE` loses none of them.
//!
//! **One op per message, never one per batch.** `message_ops` promises exactly
//! one seq per real mutation, and the client leans on it: it applies an op only
//! when its seq is exactly one past its cursor, and reconciles over REST for
//! anything else. A batch that allocated a single seq for N deletions would
//! make every connected client resync - the opposite of what a purge is for.
//!
//! Validation happens over the whole list before any row is touched, the rule
//! `canvas_ops_apply` states for the same reason: an id this caller may not
//! delete must not leave an earlier id in the same request already gone while
//! the request as a whole fails.

use sqlx::QueryBuilder;

use super::attachments::release_message_attachments;
use super::message_ops::insert_message_op;
use super::moderation_audit::{ModerationAudit, record_moderation_audit};
use super::{Store, now_ms};
use crate::ids::{ChannelId, MessageId, UserId};

/// What one bulk delete did, per message it actually deleted.
///
/// One entry per message rather than a total, because the caller has to
/// publish an event carrying that message's own op seq, the shape the
/// retention sweep's own result already uses.
#[derive(Debug, Default)]
pub struct BulkDeletion {
    pub deleted: Vec<DeletedMessage>,
    pub freed_attachments: Vec<String>,
}

#[derive(Debug)]
pub struct DeletedMessage {
    pub message_id: MessageId,
    pub op_seq: i64,
}

/// Why a bulk delete refused, before it wrote anything.
///
/// Plain enum with hand-written `From`s, the shape `RemoveMemberError` uses;
/// this crate carries no `thiserror`.
#[derive(Debug)]
pub enum BulkDeleteError {
    /// No message with that id lives in this channel.
    NotFound(MessageId),
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for BulkDeleteError {
    fn from(err: sqlx::Error) -> Self {
        BulkDeleteError::Internal(err.into())
    }
}

impl From<anyhow::Error> for BulkDeleteError {
    fn from(err: anyhow::Error) -> Self {
        BulkDeleteError::Internal(err)
    }
}

impl Store {
    /// The authors of [ids] that exist in [channel_id], for the caller to check
    /// before committing to anything.
    ///
    /// Separate from the delete itself so the permission pass can run on real
    /// authors with no transaction open: containment is the caller's rule, and
    /// it needs to answer for every id before the first row moves.
    ///
    /// A message already soft-deleted still resolves. Deleting one again has to
    /// succeed rather than 404, the same reason the single path fetches
    /// including deleted, and its author is still the author.
    pub async fn message_authors_in(
        &self,
        channel_id: ChannelId,
        ids: &[MessageId],
    ) -> Result<Vec<(MessageId, Option<UserId>)>, BulkDeleteError> {
        let mut found: Vec<(MessageId, Option<UserId>)> = Vec::with_capacity(ids.len());
        for id in ids {
            let row = sqlx::query!(
                r#"SELECT author_id AS "author_id?: UserId" FROM messages
               WHERE id = ? AND channel_id = ?"#,
                id,
                channel_id
            )
            .fetch_optional(&self.pool)
            .await?;
            let Some(row) = row else {
                return Err(BulkDeleteError::NotFound(*id));
            };
            found.push((*id, row.author_id));
        }
        Ok(found)
    }

    /// Soft-deletes every id in [ids] that is still live, as one transaction.
    ///
    /// Returns only what it actually deleted: an id already gone is not an
    /// error and produces no op and no event, which is the single path's own
    /// idempotence carried over unchanged.
    ///
    /// [subjects] is the set of authors whose messages these are, one audit row
    /// each. It is passed in rather than derived here because the caller has
    /// already resolved them to run its permission checks, and resolving them
    /// twice would let the two answers disagree.
    pub async fn bulk_delete_messages(
        &self,
        channel_id: ChannelId,
        ids: &[MessageId],
        actor_id: UserId,
        subjects: &[UserId],
    ) -> anyhow::Result<BulkDeletion> {
        if ids.is_empty() {
            return Ok(BulkDeletion::default());
        }
        let now = now_ms();
        let mut tx = self.begin_write().await?;

        let mut builder = QueryBuilder::new("UPDATE messages SET deleted_at = ");
        builder.push_bind(now);
        builder.push(" WHERE channel_id = ");
        builder.push_bind(channel_id);
        builder.push(" AND deleted_at IS NULL AND id IN (");
        let mut separated = builder.separated(", ");
        for id in ids {
            separated.push_bind(*id);
        }
        builder.push(") RETURNING id");
        let claimed: Vec<MessageId> = builder
            .build_query_scalar::<MessageId>()
            .fetch_all(&mut *tx)
            .await?;

        let mut deleted = Vec::with_capacity(claimed.len());
        let mut freed_attachments = Vec::new();
        for message_id in claimed {
            let op_seq = insert_message_op(
                &mut tx,
                channel_id,
                message_id,
                "delete",
                Some(actor_id),
                now,
            )
            .await?;
            freed_attachments.extend(release_message_attachments(&mut tx, message_id).await?);
            deleted.push(DeletedMessage { message_id, op_seq });
        }

        // Only when something was actually removed: an act that deleted nothing
        // is not an act, the rule the removal and timeout undo paths already keep.
        if !deleted.is_empty() {
            for subject_id in subjects {
                record_moderation_audit(
                    &mut tx,
                    ModerationAudit {
                        actor_id,
                        subject_id: *subject_id,
                        action: "messages_deleted",
                        reason: None,
                        until: None,
                        created_at: now,
                    },
                )
                .await?;
            }
        }

        tx.commit().await?;
        Ok(BulkDeletion {
            deleted,
            freed_attachments,
        })
    }
}
