// SPDX-License-Identifier: AGPL-3.0-only
//! Joining a channel's voice room.
//!
//! Two routes, and almost all of each is the check in front: the token this
//! hands back is a bearer credential the SFU trusts, so what a caller may do in
//! a room is decided here, once, from their permissions in that channel.
//!
//! Eviction is the other half of that. A minted token cannot be revoked, so its
//! TTL bounds how long a removed participant could walk back in; removing them
//! from the room is what makes a kick take effect now rather than in two
//! minutes.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::post;
use axum::{Json, Router};
use serde::Serialize;

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, enforce};
use super::messages::parse_uuid;
use crate::ids::{ChannelId, UserId};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::voice::{RoomToken, VoiceError};

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/channels/{channel_id}/voice/token", post(token))
        .route(
            "/channels/{channel_id}/voice/participants/{user_id}/kick",
            post(kick),
        )
}

#[derive(Serialize)]
struct TokenResponse {
    url: String,
    room: String,
    token: String,
    expires_at: i64,
    can_publish: bool,
}

impl From<RoomToken> for TokenResponse {
    fn from(t: RoomToken) -> Self {
        Self {
            url: t.url,
            room: t.room,
            token: t.token,
            expires_at: t.expires_at,
            can_publish: t.can_publish,
        }
    }
}

/// Mints a short-lived join token for this channel's voice room.
///
/// `CONNECT` is the gate. `SPEAK` and `USE_CANVAS` are not checked here as
/// pass or fail: they are carried into the token as grants, so somebody with
/// listen-only rights gets in with a token that cannot publish, and the SFU
/// enforces that rather than the client being trusted to hide a button.
///
/// A nonexistent channel grants no permissions, so it refuses identically to a
/// channel the caller may not join, revealing neither.
async fn token(
    Authed(ctx): Authed,
    parts: Parts,
    Path(channel_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<TokenResponse>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);

    let permissions = state
        .store
        .permissions_in_channel(ctx.user_id, channel_id)
        .await?;
    let needed = Permissions::VIEW_CHANNEL.union(Permissions::CONNECT);
    if !permissions.contains(needed) {
        return Err(ApiError::Forbidden);
    }

    // The name on the token is what other participants see, so it comes from
    // the account rather than from anything the caller sends with the request.
    let profile = state.store.user_profile(ctx.user_id).await?;
    let display_name = profile
        .as_ref()
        .map(|u| u.display_name.as_str())
        .unwrap_or("unknown");

    match state
        .voice
        .mint(channel_id, ctx.user_id, permissions, display_name)
    {
        Ok(token) => Ok(Json(token.into())),
        // A deployment with no SFU is a supported configuration, not a fault,
        // so it says so plainly enough for a client to hide voice entirely.
        Err(VoiceError::Unavailable) => Err(ApiError::NotConfigured(
            "this server has no voice configured",
        )),
        Err(VoiceError::Internal(err)) => Err(err.into()),
    }
}

/// Evicts a participant from a channel's voice room.
///
/// Gated on `KICK_MEMBERS` in that channel, evaluated per channel rather than
/// deployment-wide, so a moderator's rights follow the same shape as every
/// other channel action here.
///
/// Idempotent: removing somebody who is not in the room succeeds. The SFU is
/// the authority on who is connected, and a client that retries after a
/// timeout must not be told the kick failed when it landed.
///
/// This does not stop them asking for a new token. It is not meant to: taking
/// away `CONNECT` is what bars someone from a room, and this is what makes that
/// take effect immediately instead of whenever their current token lapses.
///
/// A configured SFU that cannot be reached answers 503, not 500: that is
/// upstream being down rather than this server malfunctioning, and it is the
/// difference a caller needs to decide whether retrying is worth anything.
async fn kick(
    Authed(ctx): Authed,
    parts: Parts,
    Path((channel_id, user_id)): Path<(String, String)>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    let target = UserId(parse_uuid(&user_id)?);

    let permissions = state
        .store
        .permissions_in_channel(ctx.user_id, channel_id)
        .await?;
    if !permissions.contains(Permissions::VIEW_CHANNEL.union(Permissions::KICK_MEMBERS)) {
        return Err(ApiError::Forbidden);
    }

    match state.voice.remove_participant(channel_id, target).await {
        Ok(()) => Ok(StatusCode::NO_CONTENT),
        Err(VoiceError::Unavailable) => Err(ApiError::NotConfigured(
            "this server has no voice configured",
        )),
        // Unreachable SFU is a 503, not a 500; see the note on this function.
        Err(VoiceError::Internal(err)) => {
            tracing::warn!(%err, "could not evict a voice participant");
            Err(ApiError::Unavailable)
        }
    }
}
