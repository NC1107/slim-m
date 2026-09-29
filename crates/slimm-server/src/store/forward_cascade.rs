// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Removing the forwarded copies of a message that is going away.
//!
//! A copy is a snapshot of text that someone deleted or that aged out, so it
//! goes with the original rather than outliving it. It is an ordinary soft
//! delete with its own op, so live clients, cold reads and op-stream sync all
//! see it through the paths they already have for a deleted message.

use sqlx::{QueryBuilder, Sqlite, Transaction};

use super::attachments::release_message_attachments;
use super::message_ops::insert_message_op;
use crate::ids::{ChannelId, MessageId, UserId};

/// Bounds one lookup's bound-variable count, well under SQLite's limit.
const ORIGIN_CHUNK: usize = 500;

/// One copy removed because its original went, with what the caller must
/// publish once the transaction has committed.
#[derive(Debug, Clone)]
pub struct CascadedDeletion {
    pub channel_id: ChannelId,
    pub message_id: MessageId,
    pub op_seq: i64,
    pub was_pinned: bool,
    pub freed_attachments: Vec<String>,
}

/// Live copies of any of `origins`, with the channel each lives in.
pub(super) async fn live_copies_of(
    tx: &mut Transaction<'_, Sqlite>,
    origins: &[MessageId],
) -> Result<Vec<(MessageId, ChannelId)>, sqlx::Error> {
    use sqlx::Row;

    let mut copies = Vec::new();
    for chunk in origins.chunks(ORIGIN_CHUNK) {
        let mut query = QueryBuilder::new(
            "SELECT m.id, m.channel_id FROM message_forwards f \
             JOIN messages m ON m.id = f.message_id \
             WHERE m.deleted_at IS NULL AND f.origin_message_id IN (",
        );
        let mut separated = query.separated(", ");
        for id in chunk {
            separated.push_bind(*id);
        }
        query.push(")");
        for row in query.build().fetch_all(&mut **tx).await? {
            copies.push((row.try_get("id")?, row.try_get("channel_id")?));
        }
    }
    Ok(copies)
}

/// Soft-deletes every live copy of `origins` inside the caller's transaction,
/// mirroring what `Store::delete_message` does for one message.
pub(super) async fn delete_forward_copies(
    tx: &mut Transaction<'_, Sqlite>,
    origins: &[MessageId],
    actor_id: Option<UserId>,
    now: i64,
) -> Result<Vec<CascadedDeletion>, sqlx::Error> {
    let mut removed = Vec::new();
    for (message_id, channel_id) in live_copies_of(tx, origins).await? {
        let was_pinned = sqlx::query_scalar!(
            r#"SELECT EXISTS(SELECT 1 FROM pinned_messages WHERE message_id = ?) AS "p!: bool""#,
            message_id
        )
        .fetch_one(&mut **tx)
        .await?;
        let claimed = sqlx::query!(
            "UPDATE messages SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL",
            now,
            message_id
        )
        .execute(&mut **tx)
        .await?
        .rows_affected();
        if claimed == 0 {
            continue;
        }
        let op_seq = insert_message_op(tx, channel_id, message_id, "delete", actor_id, now).await?;
        let freed_attachments = release_message_attachments(tx, message_id).await?;
        removed.push(CascadedDeletion {
            channel_id,
            message_id,
            op_seq,
            was_pinned,
            freed_attachments,
        });
    }
    Ok(removed)
}
