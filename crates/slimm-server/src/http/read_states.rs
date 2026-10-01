// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! `GET /read-states`: the caller's own read marker in every channel they can
//! read, so a client signing in asks once instead of once per channel.

use axum::Router;
use axum::extract::State;
use axum::routing::get;
use serde::Serialize;

use super::AppState;
use super::error::ApiError;
use super::extract::{AUTHED_READ, AuthedLimited, Json};
use super::sync::ReadStateDto;
use crate::ids::ChannelId;
use crate::permissions::Permissions;

pub fn routes() -> Router<AppState> {
    Router::new().route("/read-states", get(list_read_states))
}

#[derive(Serialize)]
struct ChannelReadStateDto {
    channel_id: String,
    #[serde(flatten)]
    state: ReadStateDto,
}

/// Answers for exactly the channels `GET /channels` and `GET /dms` would
/// list, plus DMs the caller hid, because the per-channel route answers those
/// too. Nobody else's marker is ever read: the store query is keyed on the
/// caller's id.
async fn list_read_states(
    AuthedLimited(ctx): AuthedLimited<AUTHED_READ>,
    State(state): State<AppState>,
) -> Result<Json<Vec<ChannelReadStateDto>>, ApiError> {
    let mut readable: Vec<ChannelId> = state
        .store
        .visible_channels(ctx.user_id)
        .await?
        .into_iter()
        .map(|channel| channel.id)
        .collect();
    let dm_ids = state.store.dm_channel_ids_for_user(ctx.user_id).await?;
    let dm_permissions = state
        .store
        .permissions_in_channels(ctx.user_id, &dm_ids)
        .await?;
    readable.extend(dm_ids.into_iter().filter(|id| {
        dm_permissions
            .get(id)
            .is_some_and(|granted| granted.contains(Permissions::VIEW_CHANNEL))
    }));

    let states = state.store.read_states_for(ctx.user_id, &readable).await?;
    Ok(Json(
        states
            .into_iter()
            .map(|read| ChannelReadStateDto {
                channel_id: read.channel_id.to_string(),
                state: ReadStateDto {
                    last_read_seq: read.last_read_seq,
                    unread: read.unread,
                    manually_unread: read.manually_unread,
                },
            })
            .collect(),
    ))
}
