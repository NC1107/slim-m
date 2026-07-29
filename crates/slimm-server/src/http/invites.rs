// SPDX-License-Identifier: AGPL-3.0-only
//! Invite routes: creating, listing, checking, and redeeming.
//!
//! Checking a code is unauthenticated, because it happens before someone has an
//! account, and rate limited (`Class::InviteCheck`) because it is. An unusable
//! code (expired, spent, revoked, or never issued) answers with exactly
//! `{"usable": false}`, byte for byte, so it cannot be used to mine valid
//! codes by telling them apart. A usable code additionally discloses what it
//! unlocks (the community's name and size, who invited the caller, and how
//! much of the code is left): reaching that branch already proves the caller
//! holds a working code, so it discloses nothing they had not already
//! demonstrated. See [`crate::store::InviteCheck`] for where that boundary is
//! enforced.

use axum::Router;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{get, post};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, INVITE_CHECK, Json, RateLimited, enforce};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::{Invite, InviteCheck, RedeemError};

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
    /// The role this code grants, or null.
    role_grant: Option<String>,
}

fn dto(invite: Invite, now: i64) -> InviteDto {
    InviteDto {
        usable: invite.is_usable(now),
        role_grant: invite.role_grant.map(|id| id.to_string()),
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
    /// A role every account redeeming this code receives. Null grants none.
    #[serde(default)]
    role_grant: Option<String>,
}

#[derive(Serialize)]
struct CheckResponse {
    /// Whether this code can be redeemed right now. Deliberately the only
    /// signal for an unusable code: saying *why* not would let someone probe
    /// for real codes.
    usable: bool,
    /// Present only when `usable` is true; see the module doc comment for
    /// why that boundary is the one that matters, not `skip_serializing_if`
    /// on the fields below it.
    #[serde(skip_serializing_if = "Option::is_none")]
    community: Option<InviteCommunity>,
}

#[derive(Serialize)]
struct InviteCommunity {
    /// This deployment's display name.
    name: String,
    /// How many live accounts the deployment has.
    member_count: i64,
    /// The inviter's current display name; null if their account has since
    /// been deleted.
    invited_by: Option<String>,
    /// Null means unlimited.
    uses_remaining: Option<i64>,
    /// Unix milliseconds; null means it never expires.
    expires_at: Option<i64>,
}

/// Resolves a requested role grant, refusing every way it could be an
/// escalation.
///
/// An invite that grants a role assigns that role to whoever redeems it, so it
/// is role assignment with a delay and must be gated exactly as `PUT
/// /members/{id}/roles/{id}` is: MANAGE_ROLES on top of CREATE_INVITE, and the
/// role's permissions already held by the caller. Without the second check,
/// CREATE_INVITE plus MANAGE_ROLES would mint an administrator account for
/// somebody holding neither bit.
async fn resolve_grant(
    state: &AppState,
    caller: crate::ids::UserId,
    raw: &str,
) -> Result<crate::ids::RoleId, ApiError> {
    let permissions = state.store.base_permissions(caller).await?;
    if !permissions.contains(Permissions::MANAGE_ROLES) {
        return Err(ApiError::Forbidden);
    }
    let role_id = crate::ids::RoleId(
        raw.parse::<uuid::Uuid>()
            .map_err(|_| ApiError::BadRequest("invalid role id"))?,
    );
    let role = state
        .store
        .role(role_id)
        .await?
        .ok_or(ApiError::NotFound("role not found"))?;
    if !permissions.contains(role.permissions) {
        return Err(ApiError::Forbidden);
    }
    Ok(role_id)
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

    let role_grant = match req.role_grant.as_deref() {
        None => None,
        Some(raw) => Some(resolve_grant(&state, ctx.user_id, raw).await?),
    };

    let invite = state
        .store
        .create_invite(ctx.user_id, role_grant, req.max_uses, req.expires_at)
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
/// holding it does not have an account yet. Rate limited because of that:
/// see the module doc comment for why a usable code is worth more to guess
/// for than before.
async fn check(
    _limited: RateLimited<INVITE_CHECK>,
    Path(code): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<CheckResponse>, ApiError> {
    match state.store.check_invite(&code).await? {
        InviteCheck::Unusable => Ok(Json(CheckResponse {
            usable: false,
            community: None,
        })),
        InviteCheck::Usable(meta) => {
            let name = state.store.deployment_name().await?;
            let member_count = state.store.member_count().await?;
            Ok(Json(CheckResponse {
                usable: true,
                community: Some(InviteCommunity {
                    name,
                    member_count,
                    invited_by: meta.invited_by,
                    uses_remaining: meta.uses_remaining,
                    expires_at: meta.expires_at,
                }),
            }))
        }
    }
}

/// Spends an invite for the signed-in account.
async fn redeem(
    Authed(ctx): Authed,
    parts: Parts,
    Path(code): Path<String>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    // Charged as a write: every attempt, hit or miss, opens the single-writer
    // transaction, so an unthrottled loop of garbage codes serialised the whole
    // server on the write lock while proving nothing.
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    match state.store.redeem_invite(&code, ctx.user_id).await {
        Ok(()) => Ok(StatusCode::NO_CONTENT),
        // One answer for expired, spent, revoked, and never-existed.
        Err(RedeemError::Unusable) => Err(ApiError::BadRequest("that invite cannot be used")),
        Err(RedeemError::Internal(e)) => Err(e.into()),
    }
}
