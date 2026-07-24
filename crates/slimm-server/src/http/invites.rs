// SPDX-License-Identifier: AGPL-3.0-only
//! Invite routes: creating, listing, checking, and redeeming.
//!
//! Checking a code is unauthenticated, because it happens before someone has an
//! account. It answers only usable or not, never why, so the endpoint cannot be
//! used to mine valid codes: an expired code, a spent code, and a code that was
//! never issued are indistinguishable.

use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::Authed;
use crate::permissions::Permissions;
use crate::store::{Invite, RedeemError};

const BODY_LIMIT: usize = 4 * 1024;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/invites", get(list).post(create))
        .route("/invites/{code}", axum::routing::delete(revoke))
        .route("/invites/{code}/check", get(check))
        .route("/invites/{code}/redeem", post(redeem))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

#[derive(Serialize)]
struct InviteDto {
    code: String,
    max_uses: Option<i64>,
    uses: i64,
    expires_at: Option<i64>,
    created_at: i64,
    revoked: bool,
    usable: bool,
}

fn dto(invite: Invite, now: i64) -> InviteDto {
    InviteDto {
        usable: invite.is_usable(now),
        code: invite.code,
        max_uses: invite.max_uses,
        uses: invite.uses,
        expires_at: invite.expires_at,
        created_at: invite.created_at,
        revoked: invite.revoked,
    }
}

#[derive(Deserialize)]
struct CreateRequest {
    /// Null means unlimited.
    max_uses: Option<i64>,
    /// Unix milliseconds; null means it never expires.
    expires_at: Option<i64>,
}

#[derive(Serialize)]
struct CheckResponse {
    /// Whether this code can be redeemed right now. Deliberately the only
    /// signal: saying *why* not would let someone probe for real codes.
    usable: bool,
}

fn now_ms() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Creates an invite. Requires the permission to manage invites.
async fn create(
    Authed(ctx): Authed,
    State(state): State<AppState>,
    Json(req): Json<CreateRequest>,
) -> Result<Json<InviteDto>, ApiError> {
    if !state
        .store
        .base_permissions(ctx.user_id)
        .await?
        .contains(Permissions::CREATE_INVITE)
    {
        return Err(ApiError::Forbidden);
    }
    if req.max_uses.is_some_and(|max| max < 1) {
        return Err(ApiError::BadRequest("max_uses must be at least 1"));
    }

    let invite = state
        .store
        .create_invite(ctx.user_id, None, req.max_uses, req.expires_at)
        .await?;
    Ok(Json(dto(invite, now_ms())))
}

async fn list(
    Authed(ctx): Authed,
    State(state): State<AppState>,
) -> Result<Json<Vec<InviteDto>>, ApiError> {
    if !state
        .store
        .base_permissions(ctx.user_id)
        .await?
        .contains(Permissions::CREATE_INVITE)
    {
        return Err(ApiError::Forbidden);
    }
    let now = now_ms();
    let invites = state.store.list_invites().await?;
    Ok(Json(invites.into_iter().map(|i| dto(i, now)).collect()))
}

async fn revoke(
    Authed(ctx): Authed,
    Path(code): Path<String>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    if !state
        .store
        .base_permissions(ctx.user_id)
        .await?
        .contains(Permissions::CREATE_INVITE)
    {
        return Err(ApiError::Forbidden);
    }
    state.store.revoke_invite(&code).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Checks a code before signup. Unauthenticated by necessity: the person
/// holding it does not have an account yet.
async fn check(
    Path(code): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<CheckResponse>, ApiError> {
    let usable = state.store.invite_is_usable(&code).await?;
    Ok(Json(CheckResponse { usable }))
}

/// Spends an invite for the signed-in account.
async fn redeem(
    Authed(ctx): Authed,
    Path(code): Path<String>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    match state.store.redeem_invite(&code, ctx.user_id).await {
        Ok(()) => Ok(StatusCode::NO_CONTENT),
        // One answer for expired, spent, revoked, and never-existed.
        Err(RedeemError::Unusable) => Err(ApiError::BadRequest("that invite cannot be used")),
        Err(RedeemError::Internal(e)) => Err(e.into()),
    }
}
