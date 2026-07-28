// SPDX-License-Identifier: AGPL-3.0-only
//! Joining a channel's voice room, and seeing who else already has.
//!
//! Three routes, and almost all of each is the check in front: the token this
//! hands back is a bearer credential the SFU trusts, so what a caller may do in
//! a room is decided here, once, from their permissions in that channel.
//!
//! Eviction is the other half of that. A minted token cannot be revoked, so its
//! TTL bounds how long a removed participant could walk back in; removing them
//! from the room is what makes a kick take effect now rather than in two
//! minutes.
//!
//! The roster is the read-only third: `VIEW_CHANNEL` is the gate, the same bit
//! that lets a member read a text channel's messages without also being able
//! to send into it. A participant who chose to appear offline is dropped from
//! every viewer's roster but their own, the same treatment [`crate::presence`]
//! gives every other surface; see [`roster`]'s doc comment for why that is a
//! deliberate call rather than an oversight.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::Serialize;

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, enforce};
use super::messages::parse_uuid;
use crate::ids::{ChannelId, UserId};
use crate::permissions::Permissions;
use crate::presence::Visibility;
use crate::ratelimit::Class;
use crate::voice::{RoomToken, VoiceError};

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/channels/{channel_id}/voice/token", post(token))
        .route("/channels/{channel_id}/voice/roster", get(roster))
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

    // The token's name comes from the account, never from what the caller sends.
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
        // No SFU is a supported configuration, not a fault; say so plainly.
        Err(VoiceError::Unavailable) => Err(ApiError::NotConfigured(
            "this server has no voice configured",
        )),
        Err(VoiceError::Internal(err)) => Err(err.into()),
    }
}

#[derive(Serialize)]
struct RosterParticipantDto {
    user_id: String,
    display_name: String,
}

#[derive(Serialize)]
struct RosterResponse {
    participants: Vec<RosterParticipantDto>,
}

/// Who is currently connected to a channel's voice room, whether or not the
/// caller has joined it.
///
/// Gated on `VIEW_CHANNEL` alone, the same bit `listMessages` reads under:
/// seeing who is talking is exactly as sensitive as seeing what they typed,
/// and no more, so this does not also require `CONNECT`.
///
/// Appear-offline still applies here even though a room's own realtime
/// protocol has no such preference: a participant with [`Visibility::Hidden`]
/// is dropped from the roster of every viewer but themselves, structurally,
/// the same way [`crate::presence::status_for`] never lets a hidden user's
/// true state reach another viewer's payload. Joining a call with somebody
/// already still shows that person live once you are both in the room - the
/// SFU has to tell participants about each other to let them hear one
/// another - but this route is the *preview* shown before joining, and that
/// preview must not become a second way to learn a hidden user is online.
///
/// A configured SFU that cannot be reached answers 503, not 500 or an empty
/// list: an empty room and an unreachable one are different claims, and only
/// the former means nobody is there.
async fn roster(
    Authed(ctx): Authed,
    parts: Parts,
    Path(channel_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<RosterResponse>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);

    let permissions = state
        .store
        .permissions_in_channel(ctx.user_id, channel_id)
        .await?;
    if !permissions.contains(Permissions::VIEW_CHANNEL) {
        return Err(ApiError::Forbidden);
    }

    let connected = match state.voice.list_participants(channel_id).await {
        Ok(list) => list,
        Err(VoiceError::Unavailable) => {
            return Err(ApiError::NotConfigured(
                "this server has no voice configured",
            ));
        }
        Err(VoiceError::Internal(err)) => {
            tracing::warn!(%err, "could not list a channel's voice participants");
            return Err(ApiError::Unavailable);
        }
    };

    let mut participants = Vec::with_capacity(connected.len());
    for participant in connected {
        if participant.user_id != ctx.user_id {
            let visibility = state.store.presence_visibility(participant.user_id).await?;
            if visibility == Some(Visibility::Hidden) {
                continue;
            }
        }
        participants.push(RosterParticipantDto {
            user_id: participant.user_id.to_string(),
            display_name: participant.display_name,
        });
    }

    Ok(Json(RosterResponse { participants }))
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
