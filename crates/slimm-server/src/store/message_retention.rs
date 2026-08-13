// SPDX-License-Identifier: AGPL-3.0-only
//! Message retention: an opt-in, deployment-wide window past which a
//! message is pruned, on the same periodic-sweep model as
//! [`Store::sweep_expired_tokens`] and [`Store::sweep_canvas_ops`].
//!
//! A prune is an ordinary soft delete, the same shape [`Store::delete_message`]
//! already uses (`deleted_at` set, attachments released, a `message_ops`
//! `'delete'` row written) - just run in a batch, under one system actor,
//! rather than one call per caller. Content is left in place: text is small
//! next to attachment bytes, and the disk this feature actually reclaims is
//! whatever `release_message_attachments` frees.
//!
//! The half worth reading closely is what happens to the *op stream* a
//! pruned message leaves behind. `message_ops`'s own doc says a floor
//! sweep "can be added later with no wire change" - this is that sweep.
//! [`Store::reclaim_message_ops_before`] deletes `message_ops` rows older
//! than the same cutoff, which advances [`Store::earliest_message_op_seq`]'s
//! floor. A client whose op cursor now sits behind that floor gets `reset`
//! from `ops_for_scope` with no code written here at all: the mechanism
//! already existed, waiting for something to move the floor. Content pruning
//! runs first in the same tick as a matter of sequence, not because order is
//! load-bearing here: the delete op a fresh prune just wrote carries `now`,
//! and `cutoff` sits a whole retention window behind it, so no ordering of
//! these two passes could make the reclaim treat that op as stale.

use super::attachments::release_message_attachments;
use super::message_ops::insert_message_op;
use super::{Store, now_ms};
use crate::ids::{ChannelId, MessageId};

const DAY_MS: i64 = 24 * 60 * 60 * 1000;

/// Bounds how long the content-pruning pass can hold the write lock: each
/// row costs an op insert and an attachment release, so this is smaller than
/// [`OP_FLOOR_SWEEP_BATCH`], whose rows are one bare `DELETE` each.
const CONTENT_SWEEP_BATCH: i64 = 200;
/// Bounds the op-log reclaim pass.
const OP_FLOOR_SWEEP_BATCH: i64 = 2_000;

/// The largest window a caller may set, ten years. Not a real ceiling on
/// retained history - a deployment's own disk is whatever it is under
/// that - only a guard against a typo landing as an effectively-unbounded
/// value with nothing to say so.
pub const MAX_MESSAGE_RETENTION_DAYS: i64 = 3650;

/// One message the sweep pruned this tick.
#[derive(Debug, Clone)]
pub struct PrunedMessage {
    pub channel_id: ChannelId,
    pub message_id: MessageId,
    /// Always `Some`: every candidate this pass selects is still live, so
    /// the soft delete it performs always writes a fresh op.
    pub op_seq: Option<i64>,
    pub freed_attachments: Vec<String>,
}

/// What one retention sweep tick did.
#[derive(Debug, Default)]
pub struct SweptMessageRetention {
    pub pruned: Vec<PrunedMessage>,
    /// Stale `message_ops` rows the same tick reclaimed; see the module doc.
    pub ops_reclaimed: u64,
}

impl Store {
    /// The current retention window in days. `0` means disabled - keep
    /// forever - the default, and what every deployment that predates this
    /// setting keeps on upgrade.
    pub async fn message_retention_days(&self) -> anyhow::Result<i64> {
        let value = sqlx::query_scalar!(
            r#"SELECT message_retention_days AS "d!: i64" FROM space_settings WHERE id = 1"#
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(value.unwrap_or(0))
    }

    /// Sets the retention window. Callers validate `days` against
    /// [`MAX_MESSAGE_RETENTION_DAYS`] and non-negativity before reaching
    /// here; the column's own `CHECK` is the backstop.
    pub async fn set_message_retention_days(&self, days: i64) -> anyhow::Result<()> {
        let now = now_ms();
        sqlx::query!(
            "UPDATE space_settings SET message_retention_days = ?, updated_at = ? WHERE id = 1",
            days,
            now
        )
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// One sweep tick. A no-op, cheaply, whenever the window is disabled:
    /// [`Store::message_retention_days`] is the only query it runs.
    pub async fn sweep_message_retention(&self) -> anyhow::Result<SweptMessageRetention> {
        let days = self.message_retention_days().await?;
        if days <= 0 {
            return Ok(SweptMessageRetention::default());
        }
        let cutoff = now_ms() - days * DAY_MS;

        let pruned = self.prune_messages_before(cutoff).await?;
        let ops_reclaimed = self.reclaim_message_ops_before(cutoff).await?;
        Ok(SweptMessageRetention {
            pruned,
            ops_reclaimed,
        })
    }

    /// Soft-deletes up to [`CONTENT_SWEEP_BATCH`] live messages older than
    /// `cutoff`, oldest first, each exactly the way
    /// [`Store::delete_message`] does it, under one system actor
    /// (`actor_id: None`).
    async fn prune_messages_before(&self, cutoff: i64) -> anyhow::Result<Vec<PrunedMessage>> {
        let mut tx = self.begin_write().await?;
        let candidates = sqlx::query_scalar!(
            r#"SELECT id AS "id!: MessageId" FROM messages
               WHERE deleted_at IS NULL AND created_at < ?
               ORDER BY created_at ASC
               LIMIT ?"#,
            cutoff,
            CONTENT_SWEEP_BATCH
        )
        .fetch_all(&mut *tx)
        .await?;

        let now = now_ms();
        let mut pruned = Vec::with_capacity(candidates.len());
        for message_id in candidates {
            let channel_id = sqlx::query_scalar!(
                r#"UPDATE messages SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL
                   RETURNING channel_id AS "channel_id!: ChannelId""#,
                now,
                message_id
            )
            .fetch_optional(&mut *tx)
            .await?;
            let Some(channel_id) = channel_id else {
                continue;
            };
            let op_seq =
                insert_message_op(&mut tx, channel_id, message_id, "delete", None, now).await?;
            let freed_attachments = release_message_attachments(&mut tx, message_id).await?;
            pruned.push(PrunedMessage {
                channel_id,
                message_id,
                op_seq: Some(op_seq),
                freed_attachments,
            });
        }
        tx.commit().await?;
        Ok(pruned)
    }

    /// Deletes up to [`OP_FLOOR_SWEEP_BATCH`] `message_ops` rows older than
    /// `cutoff`, advancing the floor for every channel with one. One
    /// statement, so no `begin_write` is needed - see `canvas_ops_sweep.rs`
    /// for the same reasoning on its own single-statement passes.
    async fn reclaim_message_ops_before(&self, cutoff: i64) -> anyhow::Result<u64> {
        let reclaimed = sqlx::query!(
            r#"DELETE FROM message_ops WHERE (channel_id, seq) IN (
                   SELECT channel_id, seq FROM message_ops WHERE created_at < ? LIMIT ?
               )"#,
            cutoff,
            OP_FLOOR_SWEEP_BATCH
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        Ok(reclaimed)
    }
}
