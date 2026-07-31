// SPDX-License-Identifier: AGPL-3.0-only
//! Submitting a canvas mutation: `remove`, `clear`, and `restore`, the kinds
//! this slice writes to the op stream `super::canvas_ops` only reads.
//!
//! A sibling of [`super::canvas_ops`] rather than part of it, the same split
//! `super::canvas`/`super::canvas_write` already make: the read and write
//! halves of one surface stay under the review budget separately.
//!
//! This route asks no timeout question at all, unlike `place`: a timeout
//! freezes the pen, never the eraser, so a timed-out member may still remove
//! their own ink. Refusing that would make a timeout's practical effect "lock
//! the defacement in place", which is backwards.
//!
//! `MANAGE_CANVAS` gets its only meaning here: removing another member's
//! object, clearing, or restoring an op you did not author, needs it.
//! Everyone else may only erase, and undo, their own ink.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{AuthedLimited, CANVAS, Json};
use super::messages::parse_uuid;
use crate::hub::Event;
use crate::ids::{CanvasObjectId, CanvasOpId, ChannelId, Seq};
use crate::permissions::Permissions;
use crate::store::{CanvasOpRequest, MAX_REMOVE_IDS_PER_OP, SubmitOpError, SubmittedOp};

#[derive(Deserialize)]
pub(super) struct SubmitOpParams {
    /// Client-generated UUIDv7, and the idempotency key.
    id: String,
    kind: String,
    object_ids: Option<Vec<String>>,
    before_seq: Option<i64>,
    target_op: Option<String>,
}

#[derive(Serialize)]
pub(super) struct CanvasOpResultDto {
    op: CanvasOpResultOpDto,
    fresh: bool,
}

#[derive(Serialize)]
struct CanvasOpResultOpDto {
    id: String,
    seq: i64,
    kind: String,
    affected: i64,
    created_at: i64,
}

/// `POST /channels/{channel_id}/canvas/ops`.
///
/// Idempotent by `id`, exactly the way `placeCanvasObject` is: a replay
/// answers with the stored op, `fresh: false`, and publishes nothing.
pub(super) async fn submit_op(
    AuthedLimited(ctx): AuthedLimited<CANVAS>,
    Path(channel_id): Path<String>,
    State(state): State<AppState>,
    Json(params): Json<SubmitOpParams>,
) -> Result<(StatusCode, Json<CanvasOpResultDto>), ApiError> {
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    let op_id = CanvasOpId(parse_uuid(&params.id)?);

    // One per-channel evaluation, as the read and place routes both do.
    let permissions = state
        .store
        .permissions_in_channel(ctx.user_id, channel_id)
        .await?;
    if !permissions.contains(Permissions::VIEW_CHANNEL.union(Permissions::USE_CANVAS)) {
        return Err(ApiError::Forbidden);
    }
    let may_moderate = permissions.contains(Permissions::MANAGE_CANVAS);

    let request = parse_request(params)?;

    let outcome = state
        .store
        .submit_canvas_op(channel_id, ctx.user_id, op_id, may_moderate, request)
        .await;
    let outcome = match outcome {
        Ok(outcome) => outcome,
        Err(SubmitOpError::NotFound) => {
            return Err(ApiError::NotFound("that id is not in this channel"));
        }
        Err(SubmitOpError::NotAuthorized) => return Err(ApiError::Forbidden),
        Err(SubmitOpError::ChannelFull) => {
            return Err(ApiError::Conflict(
                "restoring this would exceed the canvas's object ceiling",
            ));
        }
        Err(SubmitOpError::Internal(err)) => return Err(err.into()),
    };

    // No await between the commit and this call; see `ws::permission_cache`.
    if outcome.fresh && outcome.affected > 0 {
        publish(&state, channel_id, op_id, &outcome);
    }

    Ok((StatusCode::CREATED, Json(CanvasOpResultDto::from(outcome))))
}

impl From<SubmittedOp> for CanvasOpResultDto {
    fn from(outcome: SubmittedOp) -> Self {
        Self {
            fresh: outcome.fresh,
            op: CanvasOpResultOpDto {
                id: outcome.id.to_string(),
                seq: outcome.seq,
                kind: outcome.kind,
                affected: outcome.affected,
                created_at: outcome.created_at,
            },
        }
    }
}

/// Validates the discriminated body by hand rather than through a tagged
/// serde enum, the way `super::canvas_write::PlaceParams` validates `kind`
/// before touching its other fields: `object_ids` and `before_seq` are each
/// legal on only one of the two kinds this slice accepts.
fn parse_request(params: SubmitOpParams) -> Result<CanvasOpRequest, ApiError> {
    match params.kind.as_str() {
        "remove" => {
            if params.before_seq.is_some() {
                return Err(ApiError::BadRequest("before_seq is not valid for remove"));
            }
            let ids = params
                .object_ids
                .ok_or(ApiError::BadRequest("remove needs object_ids"))?;
            if ids.is_empty() || ids.len() > MAX_REMOVE_IDS_PER_OP {
                return Err(ApiError::BadRequest(
                    "object_ids must hold between 1 and 64 ids",
                ));
            }
            let object_ids = ids
                .iter()
                .map(|raw| parse_uuid(raw).map(CanvasObjectId))
                .collect::<Result<Vec<_>, _>>()?;
            Ok(CanvasOpRequest::Remove(object_ids))
        }
        "clear" => {
            if params.object_ids.is_some() {
                return Err(ApiError::BadRequest("object_ids is not valid for clear"));
            }
            let before_seq = params
                .before_seq
                .ok_or(ApiError::BadRequest("clear needs before_seq"))?;
            if before_seq < 0 {
                return Err(ApiError::BadRequest("before_seq must not be negative"));
            }
            Ok(CanvasOpRequest::Clear { before_seq })
        }
        "restore" => {
            if params.object_ids.is_some() {
                return Err(ApiError::BadRequest("object_ids is not valid for restore"));
            }
            if params.before_seq.is_some() {
                return Err(ApiError::BadRequest("before_seq is not valid for restore"));
            }
            let target_op = params
                .target_op
                .ok_or(ApiError::BadRequest("restore needs target_op"))?;
            let target_op = CanvasOpId(parse_uuid(&target_op)?);
            Ok(CanvasOpRequest::Restore { target_op })
        }
        _ => Err(ApiError::BadRequest("unknown canvas op kind")),
    }
}

fn publish(state: &AppState, channel_id: ChannelId, op_id: CanvasOpId, outcome: &SubmittedOp) {
    match outcome.kind.as_str() {
        "remove" => state.hub.publish(Event::CanvasObjectsRemoved {
            channel_id,
            seq: Seq(outcome.seq),
            op_id,
            object_ids: outcome.touched_ids.clone(),
        }),
        "clear" => state.hub.publish(Event::CanvasCleared {
            channel_id,
            seq: Seq(outcome.seq),
            op_id,
            before_seq: Seq(outcome.cleared_before_seq.unwrap_or(0)),
        }),
        "restore" => state.hub.publish(Event::CanvasObjectsRestored {
            channel_id,
            seq: Seq(outcome.seq),
            op_id,
            object_ids: restorable_ids(&outcome.touched_ids),
        }),
        _ => {}
    }
}

/// The ids a restore's frame may name, or none past this bound; see
/// [`Event::CanvasObjectsRestored`]'s own doc for why a restore, unlike a
/// remove, cannot assume its touched set is always small.
fn restorable_ids(touched: &[CanvasObjectId]) -> Vec<CanvasObjectId> {
    if touched.len() > MAX_REMOVE_IDS_PER_OP {
        Vec::new()
    } else {
        touched.to_vec()
    }
}
