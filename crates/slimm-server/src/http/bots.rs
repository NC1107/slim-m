// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Provisioning bots, gated on MANAGE_SERVER.
//!
//! Three routes and no authorization logic of its own, which is the point: a
//! bot is a user-shaped principal, so what a bot may *do* is decided by its
//! roles through the same checks every other action uses. This file only
//! decides who may create and revoke one. See
//! `docs/decisions/0028-bot-accounts.md`.
//!
//! The token is returned exactly once, by [`create`], and is unrecoverable
//! afterwards - the same one-time-reveal shape the admin reset codes use,
//! because a credential a server can re-read is a credential a stolen database
//! hands over.
//!
//! Deliberately absent: any route a bot could use to provision another bot.
//! Creation requires MANAGE_SERVER held by the caller, and a compromised bot
//! holding that bit still cannot mint a second credential that would survive
//! revoking the first, because `require_human` refuses it.

use axum::Router;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{get, post};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, Json, enforce, require_manage_server};
use super::messages::parse_uuid;
use crate::ids::UserId;
use crate::ratelimit::Class;
use crate::store::{Bot, CreateBotError};

const BODY_LIMIT: usize = 1024;

/// Bot names follow the same rules a person's username does, so a bot is
/// mentionable and addressable exactly as any member is.
const MAX_NAME_LEN: usize = 32;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/bots", get(list).post(create))
        .route("/bots/{bot_id}/revoke", post(revoke))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

#[derive(Deserialize)]
struct CreateBotDto {
    username: String,
    display_name: Option<String>,
}

#[derive(Serialize)]
struct BotDto {
    user_id: String,
    username: String,
    display_name: String,
    created_at: i64,
    /// Absent once revoked, so a reader can see at a glance that this bot can
    /// no longer act.
    token_name: Option<String>,
    token_last_used_at: Option<i64>,
}

impl From<Bot> for BotDto {
    fn from(bot: Bot) -> Self {
        Self {
            user_id: bot.user_id.to_string(),
            username: bot.username,
            display_name: bot.display_name,
            created_at: bot.created_at,
            token_name: bot.token_name,
            token_last_used_at: bot.token_last_used_at,
        }
    }
}

/// A created bot, with its token. The only response that ever carries one.
#[derive(Serialize)]
struct NewBotDto {
    bot: BotDto,
    token: String,
}

/// Refuses a bot acting as the provisioner.
///
/// Without this, a bot granted MANAGE_SERVER could create a second bot, and
/// revoking the first would leave the second behind - so a single compromise
/// would outlive the response to it. Creation is a human act.
async fn require_human(state: &AppState, user_id: UserId) -> Result<(), ApiError> {
    if state.store.is_bot(user_id).await? {
        return Err(ApiError::Forbidden);
    }
    Ok(())
}

async fn list(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
) -> Result<Json<Vec<BotDto>>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::AuthedRead)?;
    require_manage_server(&state, ctx.user_id).await?;
    let bots = state.store.list_bots().await?;
    Ok(Json(bots.into_iter().map(BotDto::from).collect()))
}

async fn create(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
    Json(body): Json<CreateBotDto>,
) -> Result<(StatusCode, Json<NewBotDto>), ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_server(&state, ctx.user_id).await?;
    require_human(&state, ctx.user_id).await?;

    let username = body.username.trim();
    if username.is_empty() || username.chars().count() > MAX_NAME_LEN {
        return Err(ApiError::BadRequest("username must be 1 to 32 characters"));
    }
    if !username
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.' || c == '-')
    {
        return Err(ApiError::BadRequest(
            "username may contain only letters, digits, and _ . -",
        ));
    }
    let display_name = body
        .display_name
        .as_deref()
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .unwrap_or(username);
    if display_name.chars().count() > MAX_NAME_LEN {
        return Err(ApiError::BadRequest(
            "display name must be 32 characters or fewer",
        ));
    }

    match state
        .store
        .create_bot(username, display_name, ctx.user_id)
        .await
    {
        Ok(new_bot) => Ok((
            StatusCode::CREATED,
            Json(NewBotDto {
                bot: new_bot.bot.into(),
                token: new_bot.token,
            }),
        )),
        Err(CreateBotError::UsernameTaken) => Err(ApiError::Conflict("that username is taken")),
        Err(CreateBotError::Internal(err)) => Err(err.into()),
    }
}

/// Revokes a bot's token and session. The account stays, so what it wrote stays
/// attributed to it - the same thing revoking anyone's session does.
async fn revoke(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
    Path(bot_id): Path<String>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_server(&state, ctx.user_id).await?;
    let bot_id = UserId(parse_uuid(&bot_id)?);
    if !state.store.revoke_bot(bot_id).await? {
        return Err(ApiError::NotFound("no such bot"));
    }
    Ok(StatusCode::NO_CONTENT)
}
