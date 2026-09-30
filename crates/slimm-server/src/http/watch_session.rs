// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! A voice channel's shared watch position: a bot sets and re-samples it, a
//! member reads it. See
//! docs/decisions/0050-watch-party-sync-authority-and-direct-play.md.

use axum::Router;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{get, post};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{AUTHED_READ, Authed, AuthedLimited, Json, enforce};
use super::hidden_chars::is_hidden_char;
use super::messages::parse_uuid;
use crate::hub::Event;
use crate::ids::{ChannelId, UserId};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::{WatchSample, WatchSession, WatchSessionWrite, WatchWriteOutcome, now_ms};

const BODY_LIMIT: usize = 4 * 1024;
const VOICE_CHANNEL_KIND: &str = "voice";
const MAX_ITEM_ID_CHARS: usize = 128;
const MAX_TITLE_CHARS: usize = 200;
/// A week of film, well past anything a call watches.
const MAX_MS: i64 = 7 * 24 * 3600 * 1000;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route(
            "/channels/{channelId}/watch-session",
            get(get_session).put(set_session).delete(end_session),
        )
        .route("/channels/{channelId}/watch-session/tick", post(tick))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

#[derive(Serialize)]
struct WatchSessionDto {
    channel_id: String,
    bot_user_id: String,
    item_id: String,
    title: String,
    duration_ms: Option<i64>,
    playing: bool,
    position_ms: i64,
    sampled_at_ms: i64,
    epoch: i64,
    controller_user_id: Option<String>,
    /// The server clock at this read, so a reader can correct for its own skew.
    server_time_ms: i64,
}

impl WatchSessionDto {
    fn new(s: WatchSession, server_time_ms: i64) -> Self {
        Self {
            channel_id: s.channel_id.to_string(),
            bot_user_id: s.bot_user_id.to_string(),
            item_id: s.item_id,
            title: s.title,
            duration_ms: s.duration_ms,
            playing: s.playing,
            position_ms: s.position_ms,
            sampled_at_ms: s.sampled_at,
            epoch: s.epoch,
            controller_user_id: s.controller_user_id.map(|u| u.to_string()),
            server_time_ms,
        }
    }
}

/// What the room is watching and where it is; 404 when nothing is playing,
/// including a session whose bot stopped ticking.
async fn get_session(
    AuthedLimited(ctx): AuthedLimited<AUTHED_READ>,
    State(state): State<AppState>,
    Path(channel_id): Path<String>,
) -> Result<Json<WatchSessionDto>, ApiError> {
    const NONE: ApiError = ApiError::NotFound("no watch session");
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    let caller = state
        .store
        .permissions_in_channel(ctx.user_id, channel_id)
        .await?;
    if !caller.contains(Permissions::VIEW_CHANNEL) {
        return Err(NONE);
    }
    let now = now_ms();
    let session = state
        .store
        .watch_session(channel_id, now)
        .await?
        .ok_or(NONE)?;
    Ok(Json(WatchSessionDto::new(session, now)))
}

#[derive(Deserialize)]
struct SetSessionRequest {
    item_id: String,
    title: String,
    #[serde(default)]
    duration_ms: Option<i64>,
    playing: bool,
    position_ms: i64,
    /// Set when the position jumped, so readers resync rather than drift-correct.
    #[serde(default)]
    seeked: bool,
    #[serde(default)]
    controller_user_id: Option<String>,
}

fn plain_text(value: &str, max_chars: usize) -> bool {
    let trimmed = value.trim();
    !trimmed.is_empty() && value.chars().count() <= max_chars && !value.chars().any(is_hidden_char)
}

fn in_range(ms: i64) -> bool {
    (0..=MAX_MS).contains(&ms)
}

impl SetSessionRequest {
    fn validate(self) -> Result<WatchSessionWrite, ApiError> {
        if !plain_text(&self.item_id, MAX_ITEM_ID_CHARS) {
            return Err(ApiError::BadRequest("item_id is empty, too long or hidden"));
        }
        if !plain_text(&self.title, MAX_TITLE_CHARS) {
            return Err(ApiError::BadRequest("title is empty, too long or hidden"));
        }
        if !in_range(self.position_ms) || !self.duration_ms.is_none_or(in_range) {
            return Err(ApiError::BadRequest("a time is out of range"));
        }
        let controller_user_id = self
            .controller_user_id
            .as_deref()
            .map(|raw| parse_uuid(raw).map(UserId))
            .transpose()?;
        Ok(WatchSessionWrite {
            item_id: self.item_id,
            title: self.title,
            duration_ms: self.duration_ms,
            playing: self.playing,
            position_ms: self.position_ms,
            seeked: self.seeked,
            controller_user_id,
        })
    }
}

/// A bot whose own voice channel this is, or the refusal for everyone else.
async fn require_bot_in_voice_channel(
    state: &AppState,
    bot: UserId,
    channel_id: ChannelId,
) -> Result<(), ApiError> {
    if !state.store.is_bot(bot).await? {
        return Err(ApiError::Forbidden);
    }
    let channel = state
        .store
        .channel(channel_id)
        .await?
        .ok_or(ApiError::NotFound("no such channel"))?;
    if channel.kind != VOICE_CHANNEL_KIND
        || !state
            .store
            .has_permission(bot, channel_id, Permissions::VIEW_CHANNEL)
            .await?
    {
        return Err(ApiError::NotFound("no such channel"));
    }
    Ok(())
}

fn publish_tick(state: &AppState, channel_id: ChannelId, sample: WatchSample) {
    state.hub.publish(Event::WatchTick {
        channel_id,
        item_id: sample.item_id,
        playing: sample.playing,
        position_ms: sample.position_ms,
        sampled_at_ms: sample.sampled_at,
        epoch: sample.epoch,
    });
}

/// A bot states the session: a new title, a play or pause, or a seek. Also
/// fans out as a tick so viewers hear about it now rather than at the next one.
async fn set_session(
    Authed(ctx): Authed,
    parts: Parts,
    State(state): State<AppState>,
    Path(channel_id): Path<String>,
    Json(req): Json<SetSessionRequest>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    require_bot_in_voice_channel(&state, ctx.user_id, channel_id).await?;
    let write = req.validate()?;
    match state
        .store
        .put_watch_session(channel_id, ctx.user_id, &write, now_ms())
        .await?
    {
        WatchWriteOutcome::Written(sample) => publish_tick(&state, channel_id, sample),
        WatchWriteOutcome::HeldByAnotherBot => {
            return Err(ApiError::Conflict(
                "another bot is running a watch session here",
            ));
        }
    }
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
struct TickRequest {
    playing: bool,
    position_ms: i64,
}

/// A bot re-samples its session's position. The heartbeat: a session that
/// goes 30 seconds without one reads as ended, paused or not.
async fn tick(
    Authed(ctx): Authed,
    parts: Parts,
    State(state): State<AppState>,
    Path(channel_id): Path<String>,
    Json(req): Json<TickRequest>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::WatchTick)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    if !state.store.is_bot(ctx.user_id).await? {
        return Err(ApiError::Forbidden);
    }
    if !in_range(req.position_ms) {
        return Err(ApiError::BadRequest("a time is out of range"));
    }
    let sample = state
        .store
        .tick_watch_session(
            channel_id,
            ctx.user_id,
            req.playing,
            req.position_ms,
            now_ms(),
        )
        .await?
        .ok_or(ApiError::NotFound("no watch session"))?;
    publish_tick(&state, channel_id, sample);
    Ok(StatusCode::NO_CONTENT)
}

/// A bot ends its own session.
async fn end_session(
    Authed(ctx): Authed,
    parts: Parts,
    State(state): State<AppState>,
    Path(channel_id): Path<String>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    if !state.store.is_bot(ctx.user_id).await? {
        return Err(ApiError::Forbidden);
    }
    if !state
        .store
        .end_watch_session(channel_id, ctx.user_id)
        .await?
    {
        return Err(ApiError::NotFound("no watch session"));
    }
    Ok(StatusCode::NO_CONTENT)
}
