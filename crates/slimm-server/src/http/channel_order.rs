// SPDX-License-Identifier: AGPL-3.0-only
//! Setting the deployment's channel order and category placement:
//! `PUT /channels/order` takes the whole rail, grouped by category, that a
//! drag produced, applied atomically - so a move between two rail sections
//! reassigns and repositions in one request rather than a move followed by a
//! reorder that could half-apply. See
//! docs/decisions/0006-channel-categories.md.

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
use crate::ids::{ChannelCategoryId, ChannelId};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::{ChannelOrderGroup, ReorderChannelsError};

/// The channel-ordering route, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new().route("/channels/order", put(reorder))
}

#[derive(Deserialize)]
struct ReorderGroupRequest {
    /// `null` for the implicit uncategorised section.
    category_id: Option<String>,
    channel_ids: Vec<String>,
}

#[derive(Deserialize)]
struct ReorderRequest {
    categories: Vec<ReorderGroupRequest>,
}

/// Sets the deployment's channel order and category placement. Requires
/// MANAGE_CHANNELS at the deployment level, the same gate `createChannel`,
/// `updateChannel` and `deleteChannel` use. Charged the same [`Class::Write`]
/// budget as those.
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

    let groups = req
        .categories
        .iter()
        .map(|group| {
            let category_id = group
                .category_id
                .as_deref()
                .map(|id| parse_uuid(id).map(ChannelCategoryId))
                .transpose()?;
            let channel_ids = group
                .channel_ids
                .iter()
                .map(|id| parse_uuid(id).map(ChannelId))
                .collect::<Result<Vec<_>, _>>()?;
            Ok::<_, ApiError>(ChannelOrderGroup {
                category_id,
                channel_ids,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;

    match state.store.reorder_channels(&groups).await {
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
        Err(ReorderChannelsError::UnknownCategory(unknown)) => {
            let ids = unknown
                .iter()
                .map(ChannelCategoryId::to_string)
                .collect::<Vec<_>>()
                .join(", ");
            Err(ApiError::BadRequestDetail(format!(
                "named unknown category(s): {ids}"
            )))
        }
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
