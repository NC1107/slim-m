// SPDX-License-Identifier: AGPL-3.0-only
//! Setting the deployment's channel order: `PUT /channels/order` takes the
//! whole ordered list of live, non-DM channel ids a drag produced, applied
//! atomically, rather than a position PATCH per channel that could interleave
//! with another admin's drag and leave the order neither of them asked for.

use axum::Router;
use axum::extract::State;
use axum::http::request::Parts;
use axum::routing::put;
use serde::Deserialize;

use super::AppState;
use super::channels::ChannelDto;
use super::error::ApiError;
use super::extract::{Authed, Json, enforce};
use super::messages::parse_uuid;
use crate::hub::Event;
use crate::ids::ChannelId;
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::ReorderChannelsError;

/// The channel-ordering route, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new().route("/channels/order", put(reorder))
}

#[derive(Deserialize)]
struct ReorderRequest {
    channel_ids: Vec<String>,
}

/// Sets the deployment's channel order. Requires MANAGE_CHANNELS at the
/// deployment level, the same gate `createChannel`, `updateChannel` and
/// `deleteChannel` use. Charged the same [`Class::Write`] budget as those.
///
/// Publishes `ChannelUpdated` only for a channel `outcome.moved` names: a
/// no-op submission answers 200 with nothing published, or every other
/// connection would be told its cache is stale for nothing.
async fn reorder(
    Authed(ctx): Authed,
    parts: Parts,
    State(state): State<AppState>,
    Json(req): Json<ReorderRequest>,
) -> Result<Json<Vec<ChannelDto>>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    if !state
        .store
        .base_permissions(ctx.user_id)
        .await?
        .contains(Permissions::MANAGE_CHANNELS)
    {
        return Err(ApiError::Forbidden);
    }

    let ordered = req
        .channel_ids
        .iter()
        .map(|id| parse_uuid(id).map(ChannelId))
        .collect::<Result<Vec<_>, _>>()?;

    match state.store.reorder_channels(&ordered).await {
        Ok(outcome) => {
            for channel in &outcome.channels {
                if outcome.moved.contains(&channel.id) {
                    state.hub.publish(Event::ChannelUpdated(channel.clone()));
                }
            }
            Ok(Json(
                outcome.channels.into_iter().map(ChannelDto::from).collect(),
            ))
        }
        Err(ReorderChannelsError::Mismatch { missing, extra }) => Err(ApiError::BadRequestDetail(
            mismatch_message(&missing, &extra),
        )),
        Err(ReorderChannelsError::Internal(e)) => Err(e.into()),
    }
}

/// Names which channels a rejected order got wrong, so a partial list does
/// not silently leave a gap.
fn mismatch_message(missing: &[ChannelId], extra: &[ChannelId]) -> String {
    let mut parts = Vec::new();
    if !missing.is_empty() {
        let ids = join_ids(missing);
        parts.push(format!("missing live channel(s): {ids}"));
    }
    if !extra.is_empty() {
        let ids = join_ids(extra);
        parts.push(format!("named unknown or repeated channel(s): {ids}"));
    }
    parts.join("; ")
}

fn join_ids(ids: &[ChannelId]) -> String {
    ids.iter()
        .map(ChannelId::to_string)
        .collect::<Vec<_>>()
        .join(", ")
}
