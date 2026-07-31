// SPDX-License-Identifier: AGPL-3.0-only
//! Submitting a mutation to the canvas op stream: `remove` and `clear`.
//!
//! A sibling of [`super::canvas_ops`] rather than part of it, the same split
//! `http::canvas` and `http::canvas_write` already make: the read and write
//! halves of one surface stay under the review budget separately.
//!
//! Every branch here allocates one seq and writes one `canvas_ops` row in the
//! same transaction that applies the change, or it writes neither - the
//! property the whole op stream rests on. `restore` (PR 3) has no
//! representation yet; [`CanvasOpRequest`] only names the two kinds this
//! slice writes.

use anyhow::Context;

use super::{Store, now_ms};
use crate::ids::{CanvasObjectId, CanvasOpId, ChannelId, UserId};

/// Most object ids one `remove` may name in a single op.
///
/// The event this produces has to fit the WebSocket's own 4 KiB frame ceiling:
/// 64 UUID strings with separators is roughly 2.5 KiB, leaving room for the
/// envelope, and the same bound caps a single request at 64 write-locked
/// point updates.
pub const MAX_REMOVE_IDS_PER_OP: usize = 64;

/// One canvas mutation submitted through `POST /channels/{id}/canvas/ops`.
pub enum CanvasOpRequest {
    Remove(Vec<CanvasObjectId>),
    Clear { before_seq: i64 },
}

/// The result of submitting one op, fresh or replayed.
pub struct SubmittedOp {
    pub id: CanvasOpId,
    pub seq: i64,
    pub kind: String,
    pub affected: i64,
    pub created_at: i64,
    /// Whether this call is what wrote the stored op, the same meaning
    /// [`super::canvas::Placement::fresh`] carries.
    pub fresh: bool,
    /// The ids a fresh `remove` actually touched - a subset of what was
    /// requested, since an id already gone is not touched again. Empty for a
    /// `clear` (whose caller already has `before_seq` in hand) and for a
    /// replay, which never publishes and so never needs this.
    pub removed_ids: Vec<CanvasObjectId>,
    /// The fence a fresh `clear` applied. `None` for `remove` and for a
    /// replay, for the same reason `removed_ids` is empty there.
    pub cleared_before_seq: Option<i64>,
}

/// Why submitting an op failed.
pub enum SubmitOpError {
    /// An id named in the request does not resolve inside this channel -
    /// absent entirely, or belonging to another one. One answer for both, so
    /// the route is not a deployment-wide existence oracle.
    NotFound,
    /// Removing another member's object, or clearing, without `MANAGE_CANVAS`.
    NotAuthorized,
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for SubmitOpError {
    fn from(err: sqlx::Error) -> Self {
        SubmitOpError::Internal(err.into())
    }
}

impl From<anyhow::Error> for SubmitOpError {
    fn from(err: anyhow::Error) -> Self {
        SubmitOpError::Internal(err)
    }
}

struct ExistingOp {
    channel_id: ChannelId,
    seq: i64,
    kind: String,
    bound_seq: Option<i64>,
    created_at: i64,
}

struct ObjectAuth {
    author_id: Option<UserId>,
    is_dead: bool,
}

impl Store {
    /// Submits a `remove` or `clear`, idempotent by `op_id` the way placing an
    /// object is idempotent by the object's own id.
    ///
    /// `may_moderate` is the caller's already-evaluated `MANAGE_CANVAS`,
    /// resolved once by the caller alongside `VIEW_CHANNEL`/`USE_CANVAS`
    /// rather than re-read here.
    pub async fn submit_canvas_op(
        &self,
        channel_id: ChannelId,
        actor_id: UserId,
        op_id: CanvasOpId,
        may_moderate: bool,
        request: CanvasOpRequest,
    ) -> Result<SubmittedOp, SubmitOpError> {
        let mut tx = self.begin_write().await?;

        if let Some(existing) = fetch_op(&mut tx, op_id).await? {
            if existing.channel_id != channel_id {
                tx.commit().await?;
                return Err(SubmitOpError::NotFound);
            }
            let affected = affected_count_for(&mut tx, channel_id, &existing).await?;
            tx.commit().await?;
            return Ok(SubmittedOp {
                id: op_id,
                seq: existing.seq,
                kind: existing.kind,
                affected,
                created_at: existing.created_at,
                fresh: false,
                removed_ids: Vec::new(),
                cleared_before_seq: None,
            });
        }

        let now = now_ms();
        let (kind, affected, removed_ids, bound_seq) = match request {
            CanvasOpRequest::Remove(object_ids) => {
                apply_remove(
                    &mut tx,
                    channel_id,
                    actor_id,
                    may_moderate,
                    &object_ids,
                    now,
                )
                .await?
            }
            CanvasOpRequest::Clear { before_seq } => {
                if !may_moderate {
                    tx.commit().await?;
                    return Err(SubmitOpError::NotAuthorized);
                }
                let affected = sqlx::query!(
                    "UPDATE canvas_objects SET deleted_at = ?
                     WHERE channel_id = ? AND deleted_at IS NULL AND seq <= ?",
                    now,
                    channel_id,
                    before_seq
                )
                .execute(&mut *tx)
                .await?
                .rows_affected() as i64;
                ("clear", affected, Vec::new(), Some(before_seq))
            }
        };

        // An op row exists only for a real state transition; see the module doc.
        if affected == 0 {
            let seq = current_canvas_seq(&mut tx, channel_id).await?;
            tx.commit().await?;
            return Ok(SubmittedOp {
                id: op_id,
                seq,
                kind: kind.to_owned(),
                affected: 0,
                created_at: now,
                fresh: true,
                removed_ids: Vec::new(),
                cleared_before_seq: None,
            });
        }

        let seq = sqlx::query_scalar!(
            r#"UPDATE channel_seq_counters SET next_seq = next_seq + 1
               WHERE channel_id = ? AND stream = 'canvas'
               RETURNING next_seq - 1 AS "seq!: i64""#,
            channel_id
        )
        .fetch_optional(&mut *tx)
        .await?
        .context("channel has no canvas sequence counter")?;

        sqlx::query!(
            r#"INSERT INTO canvas_ops (channel_id, seq, id, kind, actor_id, bound_seq, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)"#,
            channel_id,
            seq,
            op_id,
            kind,
            actor_id,
            bound_seq,
            now
        )
        .execute(&mut *tx)
        .await?;

        for object_id in &removed_ids {
            sqlx::query!(
                "INSERT INTO canvas_op_targets (channel_id, seq, object_id) VALUES (?, ?, ?)",
                channel_id,
                seq,
                object_id
            )
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;

        Ok(SubmittedOp {
            id: op_id,
            seq,
            kind: kind.to_owned(),
            affected,
            created_at: now,
            fresh: true,
            removed_ids,
            cleared_before_seq: bound_seq,
        })
    }
}

/// Validates every id first, in request order, before touching any row: an id
/// this caller may not remove must not leave an earlier id in the same batch
/// removed while the request as a whole fails.
async fn apply_remove(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    channel_id: ChannelId,
    actor_id: UserId,
    may_moderate: bool,
    object_ids: &[CanvasObjectId],
    now: i64,
) -> Result<(&'static str, i64, Vec<CanvasObjectId>, Option<i64>), SubmitOpError> {
    let mut already_dead = Vec::with_capacity(object_ids.len());
    for object_id in object_ids {
        let Some(found) = fetch_object_for_op(tx, channel_id, *object_id).await? else {
            return Err(SubmitOpError::NotFound);
        };
        if !may_moderate && found.author_id != Some(actor_id) {
            return Err(SubmitOpError::NotAuthorized);
        }
        already_dead.push(found.is_dead);
    }

    let mut touched = Vec::new();
    for (object_id, was_dead) in object_ids.iter().zip(already_dead) {
        if was_dead {
            continue;
        }
        let rows = sqlx::query!(
            "UPDATE canvas_objects SET deleted_at = ?
             WHERE id = ? AND channel_id = ? AND deleted_at IS NULL",
            now,
            object_id,
            channel_id
        )
        .execute(&mut **tx)
        .await?
        .rows_affected();
        if rows > 0 {
            touched.push(*object_id);
        }
    }

    let affected = touched.len() as i64;
    Ok(("remove", affected, touched, None))
}

async fn fetch_op(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    id: CanvasOpId,
) -> Result<Option<ExistingOp>, sqlx::Error> {
    sqlx::query_as!(
        ExistingOp,
        r#"SELECT channel_id AS "channel_id!: ChannelId", seq AS "seq!: i64",
                  kind AS "kind!", bound_seq AS "bound_seq: i64",
                  created_at AS "created_at!: i64"
           FROM canvas_ops WHERE id = ?"#,
        id
    )
    .fetch_optional(&mut **tx)
    .await
}

async fn fetch_object_for_op(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    channel_id: ChannelId,
    id: CanvasObjectId,
) -> Result<Option<ObjectAuth>, sqlx::Error> {
    let row = sqlx::query!(
        r#"SELECT author_id AS "author_id: UserId", deleted_at AS "deleted_at: i64"
           FROM canvas_objects WHERE id = ? AND channel_id = ?"#,
        id,
        channel_id
    )
    .fetch_optional(&mut **tx)
    .await?;
    Ok(row.map(|r| ObjectAuth {
        author_id: r.author_id,
        is_dead: r.deleted_at.is_some(),
    }))
}

/// The channel's current canvas head, for the response an `affected == 0`
/// call gets when no seq was allocated: "the stream stands here, unmoved".
async fn current_canvas_seq(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    channel_id: ChannelId,
) -> Result<i64, sqlx::Error> {
    let seq = sqlx::query_scalar!(
        r#"SELECT next_seq - 1 AS "seq!: i64" FROM channel_seq_counters
           WHERE channel_id = ? AND stream = 'canvas'"#,
        channel_id
    )
    .fetch_optional(&mut **tx)
    .await?;
    Ok(seq.unwrap_or(0))
}

/// Recomputes `affected` for a replayed op, since the count itself is not a
/// stored column. A `remove`'s target rows already name exactly what it
/// touched; a `clear` shares one `now` between `deleted_at` and its own
/// `created_at`, and the single writer this database has means no other
/// write can share that millisecond, so matching on it is exact.
async fn affected_count_for(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    channel_id: ChannelId,
    op: &ExistingOp,
) -> Result<i64, sqlx::Error> {
    if op.kind == "remove" {
        sqlx::query_scalar!(
            r#"SELECT COUNT(*) AS "count!: i64" FROM canvas_op_targets
               WHERE channel_id = ? AND seq = ?"#,
            channel_id,
            op.seq
        )
        .fetch_one(&mut **tx)
        .await
    } else {
        let bound = op.bound_seq.unwrap_or(0);
        sqlx::query_scalar!(
            r#"SELECT COUNT(*) AS "count!: i64" FROM canvas_objects
               WHERE channel_id = ? AND seq <= ? AND deleted_at = ?"#,
            channel_id,
            bound,
            op.created_at
        )
        .fetch_one(&mut **tx)
        .await
    }
}
