// SPDX-License-Identifier: AGPL-3.0-only
//! Compacting `canvas_ops`: reclaiming `remove`, `clear` and `restore` rows
//! once nothing they did is still in effect, on the same periodic-sweep
//! model as [`Store::sweep_expired_tokens`] and
//! [`Store::sweep_orphaned_attachments`].
//!
//! `docs/ROADMAP.md`'s Phase 6 line asks for retention that "exempts rows
//! tied to open moderation reports" - checked against `store/reports.rs`
//! rather than assumed, and it does not apply: a report never references a
//! canvas object or op at all, so there is nothing there to exempt. The real
//! constraint is undo reachability instead: a `remove` or `clear` must
//! survive for as long as anything it touched is still dead and unrestored,
//! or deleting it makes that deletion permanently un-undoable. `place` rows
//! are never touched by any of this - `list_canvas_ops`'s own join reads a
//! placed object straight off the `place` row's own seq, so deleting one
//! would delete the object from every future replay, not the object's
//! history.
//!
//! `restore.target_op` is a plain foreign key onto `canvas_ops.id` with no
//! `ON DELETE` clause, so a `remove` or `clear` cannot be deleted while any
//! `restore` row still names it, however old that removal already is. That
//! is why this runs in two passes: eligible restores first (age alone gates
//! them, since nothing ever points at a restore's own id - `apply_restore`
//! refuses a target that is not itself a `remove` or `clear`), then removes
//! and clears, bounded by age *and* by having no remaining unrestored target
//! *and* no remaining referencing restore. `canvas_op_targets` needs no
//! cleanup of its own: its `(channel_id, seq)` foreign key already cascades.
//!
//! Nothing here changes what a compacted floor means to a reading client:
//! `list_canvas_ops` already recomputes `MIN(seq)` on every read and answers
//! `reset` to a cursor that falls behind it, the same mechanism
//! `message_ops` uses. A swept `remove`/`clear`/`restore` pair nets to no
//! visible change for any replay that crosses it - by construction, since it
//! is only ever swept once every object it named is back in the state it
//! held before that op ran - so a client that pages straight across the gap
//! arrives at the same answer either way.

use super::{Store, now_ms};

/// Roughly the roadmap's own number for the op log; unrelated to
/// `canvas_audit_log`'s own retention, which this sweep never touches.
pub const CANVAS_OP_RETENTION_MS: i64 = 30 * 24 * 60 * 60 * 1000;

/// Bounds how long one pass can hold the write lock, the same reasoning
/// `ORPHAN_SWEEP_BATCH` documents for the attachment sweep.
const CANVAS_OP_SWEEP_BATCH: i64 = 500;

/// How many rows one sweep pass reclaimed, by kind.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct SweptCanvasOps {
    pub restores: u64,
    pub removes: u64,
    pub clears: u64,
}

impl SweptCanvasOps {
    pub fn total(&self) -> u64 {
        self.restores + self.removes + self.clears
    }
}

impl Store {
    /// Deletes canvas ops old enough, and no longer needed to undo anything,
    /// across every channel. See the module doc for the retention rule.
    pub async fn sweep_canvas_ops(&self) -> anyhow::Result<SweptCanvasOps> {
        let cutoff = now_ms() - CANVAS_OP_RETENTION_MS;

        // Pass 1: restores, gated on age alone; see the module doc for why.
        let restores = sqlx::query!(
            "DELETE FROM canvas_ops WHERE id IN (
                 SELECT id FROM canvas_ops WHERE kind = 'restore' AND created_at < ? LIMIT ?
             )",
            cutoff,
            CANVAS_OP_SWEEP_BATCH
        )
        .execute(&self.pool)
        .await?
        .rows_affected();

        // Pass 2a: removes, still-dead means still guarding; see the module doc.
        let removes = sqlx::query!(
            r#"DELETE FROM canvas_ops WHERE id IN (
                   SELECT o.id FROM canvas_ops o
                   WHERE o.kind = 'remove'
                     AND o.created_at < ?1
                     AND NOT EXISTS (
                         SELECT 1 FROM canvas_ops r
                         WHERE r.kind = 'restore' AND r.target_op = o.id
                     )
                     AND NOT EXISTS (
                         SELECT 1 FROM canvas_op_targets t
                         JOIN canvas_objects obj
                           ON obj.id = t.object_id AND obj.channel_id = t.channel_id
                         WHERE t.channel_id = o.channel_id AND t.seq = o.seq
                           AND obj.deleted_at IS NOT NULL
                     )
                   LIMIT ?2
               )"#,
            cutoff,
            CANVAS_OP_SWEEP_BATCH
        )
        .execute(&self.pool)
        .await?
        .rows_affected();

        // Pass 2b: clears, guarded by the exact-timestamp fence restore_candidates uses.
        let clears = sqlx::query!(
            r#"DELETE FROM canvas_ops WHERE id IN (
                   SELECT o.id FROM canvas_ops o
                   WHERE o.kind = 'clear'
                     AND o.created_at < ?1
                     AND NOT EXISTS (
                         SELECT 1 FROM canvas_ops r
                         WHERE r.kind = 'restore' AND r.target_op = o.id
                     )
                     AND NOT EXISTS (
                         SELECT 1 FROM canvas_objects obj
                         WHERE obj.channel_id = o.channel_id
                           AND obj.seq <= o.bound_seq
                           AND obj.deleted_at = o.created_at
                     )
                   LIMIT ?2
               )"#,
            cutoff,
            CANVAS_OP_SWEEP_BATCH
        )
        .execute(&self.pool)
        .await?
        .rows_affected();

        Ok(SweptCanvasOps {
            restores,
            removes,
            clears,
        })
    }
}
