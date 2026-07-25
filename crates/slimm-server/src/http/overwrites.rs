// SPDX-License-Identifier: AGPL-3.0-only
//! Channel permission overwrites: set or clear the allow/deny pair for one
//! role or one member in one channel.
//!
//! Gated on MANAGE_ROLES *in this channel specifically* (via
//! [`crate::store::Store::permissions_in_channel`]), not the deployment-wide
//! check `http::roles` uses for role CRUD, because a channel overwrite can
//! itself grant or deny MANAGE_ROLES for that channel and the evaluator has
//! to be the one source of truth for what that resolves to. A nonexistent
//! channel grants nothing either way, so this refuses "no such channel" and
//! "not permitted here" identically, the same as every other channel-scoped
//! verb in this API.
//!
//! Only `allow` is checked against the caller's own effective permissions
//! before it is accepted: forcing a bit on is a grant, and a grant the caller
//! does not themselves hold is exactly the escalation this project treats as
//! a real vulnerability class. `deny` is a restriction, not a grant, and is
//! never gated on top of already requiring MANAGE_ROLES here.

use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::put;
use axum::{Json, Router};
use serde::Deserialize;

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, enforce};
use super::messages::parse_uuid;
use crate::ids::{ChannelId, RoleId, UserId};
use crate::permissions::Permissions;
use crate::ratelimit::Class;

/// Nothing here carries more than two integers; keep the cap tight.
const BODY_LIMIT: usize = 1024;

/// The channel overwrite routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route(
            "/channels/{channel_id}/overwrites/{kind}/{id}",
            put(set).delete(clear),
        )
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

#[derive(Deserialize)]
struct SetOverwriteRequest {
    #[serde(default)]
    allow: i64,
    #[serde(default)]
    deny: i64,
}

/// What `{kind}/{id}` resolved to.
enum Target {
    Role(RoleId),
    Member(UserId),
}

fn parse_target(kind: &str, id: &str) -> Result<Target, ApiError> {
    let id = parse_uuid(id)?;
    match kind {
        "role" => Ok(Target::Role(RoleId(id))),
        "member" => Ok(Target::Member(UserId(id))),
        _ => Err(ApiError::BadRequest("kind must be role or member")),
    }
}

/// Requires MANAGE_ROLES in this channel and returns the caller's effective
/// permissions there, reused by [`set`] as the ceiling on what it may grant.
async fn require_manage_roles_here(
    state: &AppState,
    user_id: UserId,
    channel_id: ChannelId,
) -> Result<Permissions, ApiError> {
    let permissions = state
        .store
        .permissions_in_channel(user_id, channel_id)
        .await?;
    if !permissions.contains(Permissions::MANAGE_ROLES) {
        return Err(ApiError::Forbidden);
    }
    Ok(permissions)
}

/// Sets (or replaces) an overwrite. Rejects unknown permission bits outright,
/// and rejects any `allow` bit the caller does not themselves currently hold
/// in this channel.
async fn set(
    Authed(ctx): Authed,
    parts: Parts,
    Path((channel_id, kind, id)): Path<(String, String, String)>,
    State(state): State<AppState>,
    Json(req): Json<SetOverwriteRequest>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    let caller_permissions = require_manage_roles_here(&state, ctx.user_id, channel_id).await?;
    let target = parse_target(&kind, &id)?;

    let allow = Permissions::from_bits(req.allow);
    let deny = Permissions::from_bits(req.deny);
    if !Permissions::ALL.contains(allow) || !Permissions::ALL.contains(deny) {
        return Err(ApiError::BadRequest("unknown permission bits"));
    }
    // What this write actually grants, which is not the same as its `allow`
    // bits: clearing a `deny` hands out that permission just as surely as
    // setting an `allow` does. Judging by `allow` alone let a caller who held
    // MANAGE_ROLES but not, say, MANAGE_SERVER strip an existing deny and give
    // themselves the very bit they could not have granted directly.
    let (target_type, target_id) = match target {
        Target::Role(role_id) => ("role", role_id.0),
        Target::Member(user_id) => ("member", user_id.0),
    };
    let (old_allow, old_deny) = state
        .store
        .overwrite_for(channel_id, target_type, target_id)
        .await?
        .unwrap_or((Permissions::NONE, Permissions::NONE));
    let granted = allow.remove(old_allow).union(old_deny.remove(deny));
    if !caller_permissions.contains(granted) {
        return Err(ApiError::Forbidden);
    }

    match target {
        Target::Role(role_id) => {
            if state.store.role(role_id).await?.is_none() {
                return Err(ApiError::NotFound("role not found"));
            }
            state
                .store
                .set_role_overwrite(channel_id, role_id, allow, deny)
                .await?;
        }
        Target::Member(user_id) => {
            if state.store.user_profile(user_id).await?.is_none() {
                return Err(ApiError::NotFound("user not found"));
            }
            state
                .store
                .set_member_overwrite(channel_id, user_id, allow, deny)
                .await?;
        }
    }
    Ok(StatusCode::NO_CONTENT)
}

/// Clears an overwrite. Idempotent: clearing one that is not set still
/// succeeds, so this needs no existence check on the target beyond the
/// channel itself.
async fn clear(
    Authed(ctx): Authed,
    parts: Parts,
    Path((channel_id, kind, id)): Path<(String, String, String)>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    let caller_permissions = require_manage_roles_here(&state, ctx.user_id, channel_id).await?;
    let target = parse_target(&kind, &id)?;

    // Clearing an overwrite grants back every bit it was denying, so it needs
    // the same check setting one does; otherwise the guard on `set` is trivial
    // to walk around by deleting instead of rewriting.
    let (target_type, target_id) = match target {
        Target::Role(role_id) => ("role", role_id.0),
        Target::Member(user_id) => ("member", user_id.0),
    };
    if let Some((_, old_deny)) = state
        .store
        .overwrite_for(channel_id, target_type, target_id)
        .await?
        && !caller_permissions.contains(old_deny)
    {
        return Err(ApiError::Forbidden);
    }

    match target {
        Target::Role(role_id) => {
            state
                .store
                .delete_role_overwrite(channel_id, role_id)
                .await?
        }
        Target::Member(user_id) => {
            state
                .store
                .delete_member_overwrite(channel_id, user_id)
                .await?
        }
    }
    Ok(StatusCode::NO_CONTENT)
}
