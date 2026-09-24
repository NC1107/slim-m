// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Bot command registration: advertisement, not interactions. See
//! docs/decisions/0031-bot-command-registration.md.
//!
//! `PUT /bots/commands` is a bot registering its own prefix and command list,
//! authenticated as itself - never an admin route, and never usable for a
//! second bot, per decision 0028's "a bot acts only as itself". `GET
//! /bots/{botId}/commands` is the unfiltered registration a profile popover
//! reads. `GET /channels/{channelId}/bot-commands` is the composer's own
//! discovery list: every command a caller may currently be offered in that
//! channel, across every bot that can see it, permission-hint-filtered and
//! with a revoked or removed bot's commands already gone.
//!
//! Nothing here ever runs a command. Picking a row is text substitution, the
//! same as a built-in `/shrug` - the composer sends an ordinary message and
//! the bot's own process is what recognizes and answers it, exactly as it
//! does today with no registration at all. A declared `permission` only hides
//! a row from a composer that lacks it; the server never checks it before
//! delivering the message, so a bot must still verify the sender itself.

use axum::Router;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{get, put};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{AUTHED_READ, Authed, AuthedLimited, Json};
use super::messages::parse_uuid;
use crate::ids::{ChannelId, UserId};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::{BotCommand, SetBotCommandsError, VisibleBotCommand};

const BODY_LIMIT: usize = 16 * 1024;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/bots/commands", put(set_commands))
        .route("/bots/{botId}/commands", get(get_commands))
        .route(
            "/channels/{channelId}/bot-commands",
            get(list_channel_commands),
        )
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

#[derive(Deserialize)]
struct BotCommandDto {
    name: String,
    description: String,
    #[serde(default)]
    usage: Option<String>,
    #[serde(default)]
    permission: Option<i64>,
}

impl From<BotCommandDto> for BotCommand {
    fn from(dto: BotCommandDto) -> Self {
        Self {
            name: dto.name,
            description: dto.description,
            usage: dto.usage,
            permission: dto.permission,
        }
    }
}

#[derive(Deserialize)]
struct SetBotCommandsRequest {
    prefix: String,
    #[serde(default)]
    commands: Vec<BotCommandDto>,
}

/// A registered bot with its full command list, as its own profile shows it -
/// unfiltered by any viewer's own channel or permissions.
#[derive(Serialize)]
struct BotCommandRegistrationDto {
    /// Absent for a bot that has never registered anything.
    prefix: Option<String>,
    commands: Vec<RegisteredCommandDto>,
}

#[derive(Serialize)]
struct RegisteredCommandDto {
    name: String,
    description: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    usage: Option<String>,
}

/// Bulk-overwrites the caller's own registration. Refused for anyone who is
/// not a bot: a human account has no commands to register, and there is no
/// route for setting another bot's, mirroring `bots::create`'s own
/// `require_human` in reverse.
async fn set_commands(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
    Json(body): Json<SetBotCommandsRequest>,
) -> Result<StatusCode, ApiError> {
    super::extract::enforce(&state, &parts, Some(&ctx), Class::Write)?;
    if !state.store.is_bot(ctx.user_id).await? {
        return Err(ApiError::Forbidden);
    }
    let commands: Vec<BotCommand> = body.commands.into_iter().map(BotCommand::from).collect();
    match state
        .store
        .set_bot_commands(ctx.user_id, &body.prefix, &commands)
        .await
    {
        Ok(()) => Ok(StatusCode::NO_CONTENT),
        Err(SetBotCommandsError::TooManyCommands) => Err(ApiError::BadRequest(
            "a bot may register at most 50 commands",
        )),
        Err(SetBotCommandsError::InvalidPrefix(msg) | SetBotCommandsError::InvalidCommand(msg)) => {
            Err(ApiError::BadRequest(msg))
        }
        Err(SetBotCommandsError::Internal(err)) => Err(err.into()),
    }
}

/// A bot's whole registration, for a profile popover. `None` reads as "never
/// registered", including for a non-bot or unknown id - the same clean-no-op
/// shape `GET /modules/slash-commands` gives an empty deployment, rather than
/// a 404 that would let a caller probe which ids exist.
async fn get_commands(
    AuthedLimited(_ctx): AuthedLimited<AUTHED_READ>,
    State(state): State<AppState>,
    Path(bot_id): Path<String>,
) -> Result<Json<BotCommandRegistrationDto>, ApiError> {
    let bot_id = UserId(parse_uuid(&bot_id)?);
    let registration = state.store.bot_commands(bot_id).await?;
    Ok(Json(match registration {
        Some(reg) => BotCommandRegistrationDto {
            prefix: Some(reg.prefix),
            commands: reg
                .commands
                .into_iter()
                .map(|c| RegisteredCommandDto {
                    name: c.name,
                    description: c.description,
                    usage: c.usage,
                })
                .collect(),
        },
        None => BotCommandRegistrationDto {
            prefix: None,
            commands: Vec::new(),
        },
    }))
}

#[derive(Serialize)]
struct ChannelBotCommandDto {
    bot_user_id: String,
    bot_username: String,
    bot_display_name: String,
    prefix: String,
    name: String,
    description: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    usage: Option<String>,
}

impl From<VisibleBotCommand> for ChannelBotCommandDto {
    fn from(v: VisibleBotCommand) -> Self {
        Self {
            bot_user_id: v.bot_user_id.to_string(),
            bot_username: v.bot_username,
            bot_display_name: v.bot_display_name,
            prefix: v.prefix,
            name: v.command.name,
            description: v.command.description,
            usage: v.command.usage,
        }
    }
}

/// Every bot command a caller may currently be offered in this channel - the
/// composer's own discovery list. A caller who cannot view the channel at all
/// gets an empty list, exactly what a nonexistent channel also answers, so
/// this never becomes a channel-existence oracle the way
/// `channel_permissions::get_permissions` already goes out of its way to
/// avoid: without this, an ungated command (no `permission` of its own) would
/// otherwise still show for somebody who cannot see the channel it lives in.
async fn list_channel_commands(
    AuthedLimited(ctx): AuthedLimited<AUTHED_READ>,
    State(state): State<AppState>,
    Path(channel_id): Path<String>,
) -> Result<Json<Vec<ChannelBotCommandDto>>, ApiError> {
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    let caller_permissions = state
        .store
        .permissions_in_channel(ctx.user_id, channel_id)
        .await?;
    if !caller_permissions.contains(Permissions::VIEW_CHANNEL) {
        return Ok(Json(Vec::new()));
    }
    let commands = state
        .store
        .visible_bot_commands(channel_id, caller_permissions)
        .await?;
    Ok(Json(
        commands
            .into_iter()
            .map(ChannelBotCommandDto::from)
            .collect(),
    ))
}
