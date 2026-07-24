// SPDX-License-Identifier: AGPL-3.0-only
//! Channel routes: list the channels you can see, and create one.
//!
//! Listing is filtered per caller, so a channel you cannot view is simply not
//! in your list. Creating requires MANAGE_CHANNELS, which on a fresh deployment
//! only the bootstrap admin holds.

use axum::extract::{DefaultBodyLimit, State};
use axum::routing::get;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::Authed;
use crate::permissions::Permissions;
use crate::store::Channel;

const CHANNEL_BODY_LIMIT: usize = 4 * 1024;

/// The channel routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/channels", get(list).post(create))
        .layer(DefaultBodyLimit::max(CHANNEL_BODY_LIMIT))
}

#[derive(Serialize)]
struct ChannelDto {
    id: String,
    name: String,
    kind: String,
    created_at: i64,
}

impl From<Channel> for ChannelDto {
    fn from(channel: Channel) -> Self {
        Self {
            id: channel.id.to_string(),
            name: channel.name,
            kind: channel.kind,
            created_at: channel.created_at,
        }
    }
}

#[derive(Deserialize)]
struct CreateRequest {
    name: String,
    /// "text" or "voice"; defaults to text.
    kind: Option<String>,
}

/// Lists the channels the caller can view.
async fn list(
    Authed(ctx): Authed,
    State(state): State<AppState>,
) -> Result<Json<Vec<ChannelDto>>, ApiError> {
    let mut visible = Vec::new();
    for channel in state.store.list_channels().await? {
        if state
            .store
            .has_permission(ctx.user_id, channel.id, Permissions::VIEW_CHANNEL)
            .await?
        {
            visible.push(ChannelDto::from(channel));
        }
    }
    Ok(Json(visible))
}

/// Creates a channel. Requires MANAGE_CHANNELS at the deployment level.
async fn create(
    Authed(ctx): Authed,
    State(state): State<AppState>,
    Json(req): Json<CreateRequest>,
) -> Result<Json<ChannelDto>, ApiError> {
    if !state
        .store
        .base_permissions(ctx.user_id)
        .await?
        .contains(Permissions::MANAGE_CHANNELS)
    {
        return Err(ApiError::Forbidden);
    }

    let name = req.name.trim();
    if name.is_empty() || name.chars().count() > 64 {
        return Err(ApiError::BadRequest("name must be 1 to 64 characters"));
    }
    if name.chars().any(|c| c.is_control()) {
        return Err(ApiError::BadRequest(
            "name must not contain control characters",
        ));
    }
    let kind = req.kind.as_deref().unwrap_or("text");
    if !matches!(kind, "text" | "voice") {
        return Err(ApiError::BadRequest("kind must be text or voice"));
    }

    let channel = state.store.create_channel(name, kind).await?;
    Ok(Json(channel.into()))
}
