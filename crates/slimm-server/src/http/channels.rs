// SPDX-License-Identifier: AGPL-3.0-only
//! Channel routes: list, create, rename, and soft-delete.
//!
//! Listing is filtered per caller, so a channel you cannot view is simply not
//! in your list. Every mutation - create, rename, delete - checks
//! MANAGE_CHANNELS at the deployment level (like [`Store::base_permissions`],
//! not [`Store::has_permission`]), which on a fresh deployment only the
//! bootstrap admin holds. A per-channel overwrite is deliberately not
//! consulted here: a channel-scoped check would make a delete of an
//! already-deleted channel indistinguishable from "no permission" (a deleted
//! channel evaluates to no permissions at all), breaking the idempotency a
//! retry needs. The base check also still hides which ids are real from
//! anyone without MANAGE_CHANNELS, which is the population that check is
//! actually protecting against; an existing channel manager is not an
//! attacker this needs to hide anything from.

use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{get, patch};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, enforce};
use super::messages::parse_uuid;
use crate::ids::ChannelId;
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::{Channel, DeleteChannelError};

const CHANNEL_BODY_LIMIT: usize = 4 * 1024;

/// The channel routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/channels", get(list).post(create))
        .route("/channels/{channel_id}", patch(update).delete(delete))
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

#[derive(Deserialize)]
struct UpdateChannelRequest {
    name: String,
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

    let name = validate_channel_name(&req.name)?;
    let kind = req.kind.as_deref().unwrap_or("text");
    if !matches!(kind, "text" | "voice") {
        return Err(ApiError::BadRequest("kind must be text or voice"));
    }

    let channel = state.store.create_channel(name, kind).await?;
    Ok(Json(channel.into()))
}

/// Renames a channel. Requires MANAGE_CHANNELS at the deployment level.
async fn update(
    Authed(ctx): Authed,
    parts: Parts,
    Path(channel_id): Path<String>,
    State(state): State<AppState>,
    Json(req): Json<UpdateChannelRequest>,
) -> Result<Json<ChannelDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);

    if !state
        .store
        .base_permissions(ctx.user_id)
        .await?
        .contains(Permissions::MANAGE_CHANNELS)
    {
        return Err(ApiError::Forbidden);
    }

    let name = validate_channel_name(&req.name)?;
    let channel = state
        .store
        .update_channel_name(channel_id, name)
        .await?
        .ok_or(ApiError::NotFound("channel not found"))?;
    Ok(Json(channel.into()))
}

/// Soft-deletes a channel. Requires MANAGE_CHANNELS at the deployment level.
///
/// Refuses to delete the deployment's last live channel: with zero channels
/// left nobody has anywhere to land, which is exactly why bootstrap seeds a
/// `general` channel for a fresh deployment in the first place. A second
/// delete of an already-deleted channel is not an error, matching the rest of
/// this API's delete verbs; a channel id that was never real is a plain 404,
/// same as it would be for any other resource a manager is allowed to see.
async fn delete(
    Authed(ctx): Authed,
    parts: Parts,
    Path(channel_id): Path<String>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);

    if !state
        .store
        .base_permissions(ctx.user_id)
        .await?
        .contains(Permissions::MANAGE_CHANNELS)
    {
        return Err(ApiError::Forbidden);
    }

    // Fetched regardless of `deleted_at`: a retry against an already-deleted
    // channel must succeed rather than 404, so this needs to see that row to
    // tell "already gone" apart from "never existed".
    state
        .store
        .channel_including_deleted(channel_id)
        .await?
        .ok_or(ApiError::NotFound("channel not found"))?;

    match state.store.delete_channel(channel_id).await {
        Ok(_) => Ok(StatusCode::NO_CONTENT),
        Err(DeleteChannelError::LastChannel) => Err(ApiError::Conflict(
            "cannot delete the deployment's last channel",
        )),
        Err(DeleteChannelError::Internal(e)) => Err(e.into()),
    }
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

fn validate_channel_name(name: &str) -> Result<&str, ApiError> {
    let trimmed = name.trim();
    if trimmed.is_empty() || trimmed.chars().count() > 64 {
        return Err(ApiError::BadRequest("name must be 1 to 64 characters"));
    }
    if trimmed.chars().any(|c| c.is_control()) {
        return Err(ApiError::BadRequest(
            "name must not contain control characters",
        ));
    }
    Ok(trimmed)
}
