// SPDX-License-Identifier: AGPL-3.0-only
//! Per-kind mutation logic for `submit_canvas_op`: what `remove`, `restore`
//! and `move` each authorize and touch, and the small reads they share.
//!
//! Split out of `canvas_ops_write.rs`, which crossed the 500-line hard limit
//! once `move` joined `remove`, `clear` and `restore`: that file keeps the
//! orchestrator (`Store::submit_canvas_op`) and the public request/result
//! types, this one keeps everything below the per-kind dispatch.

use sqlx::QueryBuilder;

use super::canvas::MAX_OBJECTS_PER_CHANNEL;
use super::canvas_move::move_canvas_object_query;
use super::canvas_ops_write::SubmitOpError;
use crate::ids::{CanvasObjectId, CanvasOpId, ChannelId, UserId};

/// How many objects one `UPDATE ... IN (...)` names at a time, the
/// `ORPHAN_SWEEP_BATCH`/`CANVAS_OP_SWEEP_BATCH` figure. A restore of a large
/// `clear` can carry up to `MAX_OBJECTS_PER_CHANNEL` (20,000) dead objects;
/// batching keeps the single write-lock hold under a few dozen statements
/// rather than one per object, which measured at roughly half a second held
/// against the deployment's one writer for a full channel's worth.
const RESTORE_UNDELETE_BATCH: usize = 500;

pub(super) struct ExistingOp {
    pub(super) channel_id: ChannelId,
    pub(super) seq: i64,
    pub(super) kind: String,
    pub(super) actor_id: Option<UserId>,
    pub(super) bound_seq: Option<i64>,
    pub(super) created_at: i64,
}

struct ObjectAuth {
    author_id: Option<UserId>,
    is_dead: bool,
    /// The exact moment this object was last soft-deleted, or `None` if
    /// live. Distinct from [`Self::is_dead`], which only asks *whether*: a
    /// `remove` restore has to ask *because of which removal*, or it can
    /// restore an object into a state a *different*, later removal put it
    /// in - see [`apply_restore`]'s own doc.
    deleted_at: Option<i64>,
}

/// Validates every id first, in request order, before touching any row: an id
/// this caller may not remove must not leave an earlier id in the same batch
/// removed while the request as a whole fails.
pub(super) async fn apply_remove(
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

/// Repositions one live object, authorized the same way `apply_remove` is:
/// the caller's own object needs nothing further, anyone else's needs
/// `MANAGE_CANVAS`.
///
/// Authorization is checked before liveness, not after: a non-moderator
/// naming an object they do not own must get the same `NotAuthorized`
/// whether that object is alive or already dead, or a dead check run first
/// would answer a live-versus-dead question about an object this caller was
/// never allowed to touch, off a bit no permission gates.
///
/// An object already removed answers `affected: 0` rather than an error - the
/// same "an honest retry deserves a truthful answer" reasoning `PlaceError::Removed`
/// documents, extended here since a move naming a since-erased id is exactly
/// that kind of race, not a caller mistake - but only once authorization is
/// already settled, since that reasoning was always about a caller's own
/// object racing its own removal, never about a foreign one.
///
/// Bounds are validated inside [`move_canvas_object_query`] itself, the same
/// check a placement makes, so this never duplicates it. And since this runs
/// inside the caller's own write transaction, nothing can remove `object_id`
/// between the dead-check above and the update below - single-writer is what
/// makes a `false` result here mean the row vanished by some path this module
/// does not know about, not a race this function lost.
pub(super) async fn apply_move(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    channel_id: ChannelId,
    actor_id: UserId,
    may_moderate: bool,
    object_id: CanvasObjectId,
    bounds: (f64, f64, f64, f64),
) -> Result<(&'static str, i64, Vec<CanvasObjectId>, Option<i64>), SubmitOpError> {
    let Some(found) = fetch_object_for_op(tx, channel_id, object_id).await? else {
        return Err(SubmitOpError::NotFound);
    };
    if !may_moderate && found.author_id != Some(actor_id) {
        return Err(SubmitOpError::NotAuthorized);
    }
    if found.is_dead {
        return Ok(("move", 0, Vec::new(), None));
    }
    let moved = move_canvas_object_query(&mut **tx, object_id, bounds).await?;
    if !moved {
        return Ok(("move", 0, Vec::new(), None));
    }
    Ok(("move", 1, vec![object_id], None))
}

/// Restacks one live object to an explicit `z_index`, authorized identically
/// to [`apply_move`]: the caller's own object needs nothing further, anyone
/// else's needs `MANAGE_CANVAS`, and the same ordering applies - authorization
/// is checked before liveness, for the reason `apply_move`'s own doc gives.
///
/// Unlike a move, no bounds check applies - any `i64` is a legal paint order -
/// so there is no [`SubmitOpError::OutOfBounds`] path here at all. The
/// `UPDATE` names only `z_index`, which the R-Tree trigger does not watch (see
/// migration 0015's `UPDATE OF` clause), so a reorder never touches the
/// spatial index.
pub(super) async fn apply_reorder(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    channel_id: ChannelId,
    actor_id: UserId,
    may_moderate: bool,
    object_id: CanvasObjectId,
    z_index: i64,
) -> Result<(&'static str, i64, Vec<CanvasObjectId>, Option<i64>), SubmitOpError> {
    let Some(found) = fetch_object_for_op(tx, channel_id, object_id).await? else {
        return Err(SubmitOpError::NotFound);
    };
    if !may_moderate && found.author_id != Some(actor_id) {
        return Err(SubmitOpError::NotAuthorized);
    }
    if found.is_dead {
        return Ok(("reorder", 0, Vec::new(), None));
    }
    let affected = sqlx::query!(
        "UPDATE canvas_objects SET z_index = ?
         WHERE id = ? AND channel_id = ? AND deleted_at IS NULL",
        z_index,
        object_id,
        channel_id
    )
    .execute(&mut **tx)
    .await?
    .rows_affected();
    if affected == 0 {
        return Ok(("reorder", 0, Vec::new(), None));
    }
    Ok(("reorder", 1, vec![object_id], None))
}

/// Un-deletes what `target_op` (a `remove` or `clear`) touched, refused past
/// the channel's live ceiling in the same transaction that counts it - the
/// `place_canvas_object` shape, extended to a batch.
///
/// A target that is absent, foreign, or not a `remove`/`clear` gets one 404:
/// this route is not a way to learn which of the three a bad id happens to
/// be.
///
/// Authorship of the *op* is necessary but never sufficient on its own: a
/// `clear` has no notion of "self" content at all, so undoing one always
/// needs `MANAGE_CANVAS` held *now*, and a `remove` needs the same live
/// re-check for any touched object the actor did not themselves author -
/// exactly the bit that removal needed at the time. Without this, revoking a
/// moderator's `MANAGE_CANVAS` would leave them able to keep reversing their
/// own past bulk moderation forever, using bare authorship of an op as a
/// permission that outlives the role it required. Restoring your own object
/// stays free of any role check either way, since that removal never needed
/// one either.
///
/// Authorization on the *op* is not authorization on the object's *current*
/// state: a `remove` target is only ever restored back into exactly the
/// deletion it caused (`deleted_at == target.created_at`), never into
/// whatever deletion happens to hold now. Without that fence, a member's own
/// past self-removal - which needed no `MANAGE_CANVAS` to create - would
/// stay a standing credential to undo any later, unrelated removal of the
/// same object, including one a moderator made under `MANAGE_CANVAS` for
/// cause, as long as the member still knew their own old op id. `clear`
/// already carried this exact fence in `restore_candidates`; `remove` did
/// not, and `restoring_a_stale_remove_does_not_reach_past_a_later_independent_removal`
/// (`tests/canvas_ops/restore_permission.rs`) reproduces the bypass it left
/// open.
pub(super) async fn apply_restore(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    channel_id: ChannelId,
    actor_id: UserId,
    may_moderate: bool,
    target_op: CanvasOpId,
) -> Result<(&'static str, i64, Vec<CanvasObjectId>, Option<i64>), SubmitOpError> {
    let Some(target) = fetch_op(tx, target_op).await? else {
        return Err(SubmitOpError::NotFound);
    };
    if target.channel_id != channel_id || !matches!(target.kind.as_str(), "remove" | "clear") {
        return Err(SubmitOpError::NotFound);
    }
    if !may_moderate && (target.kind == "clear" || target.actor_id != Some(actor_id)) {
        return Err(SubmitOpError::NotAuthorized);
    }

    let candidates = restore_candidates(tx, channel_id, &target).await?;

    // `restore_candidates`'s own `clear` query already proves each id dead.
    let dead = if target.kind == "clear" {
        candidates
    } else {
        let mut dead = Vec::with_capacity(candidates.len());
        for object_id in &candidates {
            let found = fetch_object_for_op(tx, channel_id, *object_id).await?;
            if !may_moderate {
                let Some(found) = &found else {
                    return Err(SubmitOpError::NotAuthorized);
                };
                if found.author_id != Some(actor_id) {
                    return Err(SubmitOpError::NotAuthorized);
                }
            }
            // Exactly the deletion this remove caused, not just any current
            // deadness - see `ObjectAuth::deleted_at`'s own doc for why.
            if found.is_some_and(|found| found.deleted_at == Some(target.created_at)) {
                dead.push(*object_id);
            }
        }
        dead
    };

    let live = sqlx::query_scalar!(
        r#"SELECT COUNT(*) AS "count!: i64" FROM canvas_objects
           WHERE channel_id = ? AND deleted_at IS NULL"#,
        channel_id
    )
    .fetch_one(&mut **tx)
    .await?;
    if live + dead.len() as i64 > MAX_OBJECTS_PER_CHANNEL {
        return Err(SubmitOpError::ChannelFull);
    }

    let touched = undelete_batch(tx, channel_id, &dead).await?;

    let affected = touched.len() as i64;
    Ok(("restore", affected, touched, None))
}

/// Un-deletes every id in `dead`, `RESTORE_UNDELETE_BATCH` at a time rather
/// than one round trip per object: each id already comes from
/// `restore_candidates`, which only ever names an object already proven dead
/// inside this same write transaction, so there is nothing left to
/// authorize here - only the row count actually flipped is worth reporting
/// back, which `RETURNING id` gives for free per batch.
async fn undelete_batch(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    channel_id: ChannelId,
    dead: &[CanvasObjectId],
) -> Result<Vec<CanvasObjectId>, sqlx::Error> {
    let mut touched = Vec::with_capacity(dead.len());
    for chunk in dead.chunks(RESTORE_UNDELETE_BATCH) {
        let mut builder =
            QueryBuilder::new("UPDATE canvas_objects SET deleted_at = NULL WHERE channel_id = ");
        builder.push_bind(channel_id);
        builder.push(" AND deleted_at IS NOT NULL AND id IN (");
        let mut separated = builder.separated(", ");
        for id in chunk {
            separated.push_bind(*id);
        }
        builder.push(") RETURNING id");
        let rows: Vec<CanvasObjectId> = builder.build_query_scalar().fetch_all(&mut **tx).await?;
        touched.extend(rows);
    }
    Ok(touched)
}

/// The objects `target` named: a `remove`'s own `canvas_op_targets` rows, or -
/// since a `clear` stores no per-object targets, only a fence - every object
/// whose `deleted_at` matches the exact moment that clear ran, which
/// `canvas_ops_write::now_ms_unique` guarantees no other op's own timestamp
/// can also equal.
async fn restore_candidates(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    channel_id: ChannelId,
    target: &ExistingOp,
) -> Result<Vec<CanvasObjectId>, sqlx::Error> {
    if target.kind == "remove" {
        sqlx::query_scalar!(
            r#"SELECT object_id AS "object_id!: CanvasObjectId" FROM canvas_op_targets
               WHERE channel_id = ? AND seq = ?"#,
            channel_id,
            target.seq
        )
        .fetch_all(&mut **tx)
        .await
    } else {
        let bound = target.bound_seq.unwrap_or(0);
        sqlx::query_scalar!(
            r#"SELECT id AS "id!: CanvasObjectId" FROM canvas_objects
               WHERE channel_id = ? AND seq <= ? AND deleted_at = ?"#,
            channel_id,
            bound,
            target.created_at
        )
        .fetch_all(&mut **tx)
        .await
    }
}

pub(super) async fn fetch_op(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    id: CanvasOpId,
) -> Result<Option<ExistingOp>, sqlx::Error> {
    sqlx::query_as!(
        ExistingOp,
        r#"SELECT channel_id AS "channel_id!: ChannelId", seq AS "seq!: i64",
                  kind AS "kind!", actor_id AS "actor_id: UserId",
                  bound_seq AS "bound_seq: i64", created_at AS "created_at!: i64"
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
        deleted_at: r.deleted_at,
    }))
}

/// The channel's current canvas head, for the response an `affected == 0`
/// call gets when no seq was allocated: "the stream stands here, unmoved".
pub(super) async fn current_canvas_seq(
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
/// stored column. A `remove`'s, `restore`'s, `move`'s or `reorder`'s own
/// target row already names exactly what it touched, all keyed by the op's
/// own seq; a `clear` shares one `now` between `deleted_at` and its own
/// `created_at`, and `canvas_ops_write::now_ms_unique` is what makes that
/// value exact rather than merely likely - see its own doc for why a plain
/// `now_ms()` was not enough.
pub(super) async fn affected_count_for(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    channel_id: ChannelId,
    op: &ExistingOp,
) -> Result<i64, sqlx::Error> {
    if op.kind == "remove" || op.kind == "restore" || op.kind == "move" || op.kind == "reorder" {
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
