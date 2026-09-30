// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! A voice channel's shared watch position: a bot sets and re-samples it, a
//! member reads it. See
//! docs/decisions/0050-watch-party-sync-authority-and-direct-play.md.
//!
//! A session belongs to one bot and lives only while that bot is on the call:
//! every write needs the bot's call heartbeat, a read hides a session whose
//! bot has none, and the bot leaving cleanly ends it with an ended tick.
//! A bot evicted for a stale heartbeat is not announced; readers see the
//! session gone at once and viewers drop it when its ticks stop. Another bot
//! may replace a session whose owner is off the call or past the lifetime
//! below, and nobody else can end it.

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
use crate::store::{
    WATCH_SESSION_TTL_MS, WatchSample, WatchSession, WatchSessionWrite, WatchWriteOutcome, now_ms,
};

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
    /// Advisory: who the bot says is steering, for display only.
    controller_user_id: Option<String>,
    /// How long after `sampled_at_ms` the session still counts as live, so a
    /// viewer hides it on the server's own rule rather than a guess.
    ttl_ms: i64,
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
            ttl_ms: WATCH_SESSION_TTL_MS,
            server_time_ms,
        }
    }
}

/// What the room is watching and where it is; 404 when nothing is playing,
/// including a session whose bot stopped ticking or left the call.
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
        .filter(|s| state.voice.has_heartbeat(s.bot_user_id, channel_id))
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
    /// `controller` is already parsed and checked against the channel.
    fn validate(self, controller: Option<UserId>) -> Result<WatchSessionWrite, ApiError> {
        if !plain_text(&self.item_id, MAX_ITEM_ID_CHARS) {
            return Err(ApiError::BadRequest("item_id is empty, too long or hidden"));
        }
        if !plain_text(&self.title, MAX_TITLE_CHARS) {
            return Err(ApiError::BadRequest("title is empty, too long or hidden"));
        }
        if !in_range(self.position_ms) || !self.duration_ms.is_none_or(in_range) {
            return Err(ApiError::BadRequest("a time is out of range"));
        }
        Ok(WatchSessionWrite {
            item_id: self.item_id,
            title: self.title,
            duration_ms: self.duration_ms,
            playing: self.playing,
            position_ms: self.position_ms,
            seeked: self.seeked,
            controller_user_id: controller,
        })
    }
}

/// The controller hint, which must be somebody who can view the channel.
async fn checked_controller(
    state: &AppState,
    channel_id: ChannelId,
    raw: Option<&str>,
) -> Result<Option<UserId>, ApiError> {
    let Some(raw) = raw else { return Ok(None) };
    const REFUSED: ApiError = ApiError::BadRequest("controller_user_id cannot view this channel");
    let user = UserId(parse_uuid(raw)?);
    if state.store.user_profile(user).await?.is_none() {
        return Err(REFUSED);
    }
    let can_view = state
        .store
        .permissions_in_channel(user, channel_id)
        .await?
        .contains(Permissions::VIEW_CHANNEL);
    if !can_view {
        return Err(REFUSED);
    }
    Ok(Some(user))
}

/// A bot that is on the call of this voice channel, or the refusal for everyone else.
async fn require_bot_in_call(
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
    require_in_call(state, bot, channel_id)
}

fn require_in_call(state: &AppState, bot: UserId, channel_id: ChannelId) -> Result<(), ApiError> {
    if state.voice.has_heartbeat(bot, channel_id) {
        Ok(())
    } else {
        Err(ApiError::ForbiddenBecause("the bot is not on this call"))
    }
}

fn publish_tick(state: &AppState, channel_id: ChannelId, sample: WatchSample, ended: bool) {
    state.hub.publish(Event::WatchTick {
        channel_id,
        bot_user_id: sample.bot_user_id,
        ended,
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
    enforce(&state, &parts, Some(&ctx), Class::WatchTick)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    require_bot_in_call(&state, ctx.user_id, channel_id).await?;
    let controller =
        checked_controller(&state, channel_id, req.controller_user_id.as_deref()).await?;
    let write = req.validate(controller)?;
    let outcome = state
        .store
        .put_watch_session(channel_id, ctx.user_id, &write, now_ms(), |owner| {
            state.voice.has_heartbeat(owner, channel_id)
        })
        .await?;
    match outcome {
        WatchWriteOutcome::Written(sample) => publish_tick(&state, channel_id, sample, false),
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
    require_in_call(&state, ctx.user_id, channel_id)?;
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
    publish_tick(&state, channel_id, sample, false);
    Ok(StatusCode::NO_CONTENT)
}

/// Ends a bot's session because it left the call, and tells the viewers.
pub(super) async fn end_for_departed(
    state: &AppState,
    user_id: UserId,
    channel_id: ChannelId,
) -> Result<(), ApiError> {
    if let Some(sample) = state.store.end_watch_session(channel_id, user_id).await? {
        publish_tick(state, channel_id, sample, true);
    }
    Ok(())
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
    let sample = state
        .store
        .end_watch_session(channel_id, ctx.user_id)
        .await?
        .ok_or(ApiError::NotFound("no watch session"))?;
    publish_tick(&state, channel_id, sample, true);
    Ok(StatusCode::NO_CONTENT)
}
