// SPDX-License-Identifier: AGPL-3.0-only
//! Role management: create, list, update, and delete roles, and grant or
//! revoke one on a member. Every verb here is gated on MANAGE_ROLES at the
//! deployment level, since roles are not scoped to any one channel.
//!
//! This is one of the highest-privilege surfaces in the product, so two
//! guards apply everywhere a permission set becomes grantable (creating a
//! role, changing one's permissions, or assigning an existing role to a
//! member): the bits involved must already be held by the caller, or holding
//! MANAGE_ROLES would be enough to hand out permissions nobody approved for
//! you to hand out, ADMINISTRATOR included. The other guard, that the
//! deployment always keeps at least one administrator, lives in
//! [`crate::store::roles`] because it has to see every caller at once, not
//! just this request's.

use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{get, patch, put};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, enforce};
use super::messages::parse_uuid;
use crate::ids::{RoleId, UserId};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::{Role, RoleGuardError};

const BODY_LIMIT: usize = 4 * 1024;

/// The role management routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/roles", get(list).post(create))
        .route("/roles/{role_id}", patch(update).delete(delete))
        .route(
            "/members/{user_id}/roles/{role_id}",
            put(assign).delete(unassign),
        )
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

// ---------------------------------------------------------------------------
// Wire types
// ---------------------------------------------------------------------------

#[derive(Serialize)]
struct RoleDto {
    id: String,
    name: String,
    /// The raw permission bitmask; see `crate::permissions::Permissions` for
    /// what each bit means.
    permissions: i64,
    is_everyone: bool,
    created_at: i64,
}

impl From<Role> for RoleDto {
    fn from(role: Role) -> Self {
        Self {
            id: role.id.to_string(),
            name: role.name,
            permissions: role.permissions.bits(),
            is_everyone: role.is_everyone,
            created_at: role.created_at,
        }
    }
}

#[derive(Deserialize)]
struct CreateRoleRequest {
    name: String,
    permissions: i64,
}

#[derive(Deserialize)]
struct UpdateRoleRequest {
    name: Option<String>,
    permissions: Option<i64>,
}

// ---------------------------------------------------------------------------
// Handlers: role CRUD
// ---------------------------------------------------------------------------

async fn list(
    Authed(ctx): Authed,
    State(state): State<AppState>,
) -> Result<Json<Vec<RoleDto>>, ApiError> {
    require_manage_roles(&state, ctx.user_id).await?;
    let roles = state.store.list_roles().await?;
    Ok(Json(roles.into_iter().map(RoleDto::from).collect()))
}

async fn create(
    Authed(ctx): Authed,
    parts: Parts,
    State(state): State<AppState>,
    Json(req): Json<CreateRoleRequest>,
) -> Result<Json<RoleDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let caller_permissions = require_manage_roles(&state, ctx.user_id).await?;

    let name = validate_role_name(&req.name)?;
    let permissions = grantable(caller_permissions, req.permissions)?;

    // Never `@everyone`: exactly one of those exists, seeded only by
    // `Store::bootstrap_deployment`, and this endpoint has no field to ask
    // for it.
    let id = state.store.create_role(name, permissions, false).await?;
    let role = state.store.role(id).await?.ok_or(ApiError::Internal)?;
    Ok(Json(role.into()))
}

async fn update(
    Authed(ctx): Authed,
    parts: Parts,
    Path(role_id): Path<String>,
    State(state): State<AppState>,
    Json(req): Json<UpdateRoleRequest>,
) -> Result<Json<RoleDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let caller_permissions = require_manage_roles(&state, ctx.user_id).await?;
    let role_id = RoleId(parse_uuid(&role_id)?);

    let name = req.name.as_deref().map(validate_role_name).transpose()?;
    let permissions = req
        .permissions
        .map(|bits| grantable(caller_permissions, bits))
        .transpose()?;
    if name.is_none() && permissions.is_none() {
        return Err(ApiError::BadRequest("nothing to update"));
    }

    match state.store.update_role(role_id, name, permissions).await {
        Ok(Some(role)) => Ok(Json(role.into())),
        Ok(None) => Err(ApiError::NotFound("role not found")),
        Err(guard_err) => Err(role_guard_error(guard_err)),
    }
}

/// Deletes a role. Refuses `@everyone` and refuses to take the deployment
/// below one administrator; both come back as 409, since either way the
/// request collided with an invariant rather than a permission the caller
/// simply lacks.
async fn delete(
    Authed(ctx): Authed,
    parts: Parts,
    Path(role_id): Path<String>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_roles(&state, ctx.user_id).await?;
    let role_id = RoleId(parse_uuid(&role_id)?);

    match state.store.delete_role(role_id).await {
        Ok(Some(())) => Ok(StatusCode::NO_CONTENT),
        Ok(None) => Err(ApiError::NotFound("role not found")),
        Err(guard_err) => Err(role_guard_error(guard_err)),
    }
}

// ---------------------------------------------------------------------------
// Handlers: member role assignment
// ---------------------------------------------------------------------------

/// Grants a role to a member. Idempotent. Refused if the role carries a
/// permission the caller does not themselves hold, since granting a role is
/// granting whatever it carries.
async fn assign(
    Authed(ctx): Authed,
    parts: Parts,
    Path((user_id, role_id)): Path<(String, String)>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let caller_permissions = require_manage_roles(&state, ctx.user_id).await?;
    let user_id = UserId(parse_uuid(&user_id)?);
    let role_id = RoleId(parse_uuid(&role_id)?);

    let role = state
        .store
        .role(role_id)
        .await?
        .ok_or(ApiError::NotFound("role not found"))?;
    if !caller_permissions.contains(role.permissions) {
        return Err(ApiError::Forbidden);
    }

    state.store.assign_role(user_id, role_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Revokes a role from a member. Idempotent, and refused if it would leave
/// the deployment with no administrator.
async fn unassign(
    Authed(ctx): Authed,
    parts: Parts,
    Path((user_id, role_id)): Path<(String, String)>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_roles(&state, ctx.user_id).await?;
    let user_id = UserId(parse_uuid(&user_id)?);
    let role_id = RoleId(parse_uuid(&role_id)?);

    match state.store.unassign_role(user_id, role_id).await {
        Ok(()) => Ok(StatusCode::NO_CONTENT),
        Err(guard_err) => Err(role_guard_error(guard_err)),
    }
}

// ---------------------------------------------------------------------------
// Shared checks
// ---------------------------------------------------------------------------

/// Requires MANAGE_ROLES at the deployment level and returns the caller's
/// full base permission set, so the handler can reuse it for the escalation
/// check without a second lookup.
async fn require_manage_roles(state: &AppState, user_id: UserId) -> Result<Permissions, ApiError> {
    let permissions = state.store.base_permissions(user_id).await?;
    if !permissions.contains(Permissions::MANAGE_ROLES) {
        return Err(ApiError::Forbidden);
    }
    Ok(permissions)
}

/// Validates that `bits` names only defined permissions and that every one of
/// them is already held by `caller`, so MANAGE_ROLES alone can never be used
/// to hand out a permission the caller lacks. An administrator's `caller`
/// already resolves to [`Permissions::ALL`], so this is also where that
/// bypass takes effect.
fn grantable(caller: Permissions, bits: i64) -> Result<Permissions, ApiError> {
    let requested = Permissions::from_bits(bits);
    if !Permissions::ALL.contains(requested) {
        return Err(ApiError::BadRequest("unknown permission bits"));
    }
    if !caller.contains(requested) {
        return Err(ApiError::Forbidden);
    }
    Ok(requested)
}

fn role_guard_error(err: RoleGuardError) -> ApiError {
    match err {
        RoleGuardError::IsEveryone => ApiError::Conflict("the @everyone role cannot be deleted"),
        RoleGuardError::LastAdministrator => {
            ApiError::Conflict("this would leave the deployment with no administrator")
        }
        RoleGuardError::Internal(e) => e.into(),
    }
}

fn validate_role_name(name: &str) -> Result<&str, ApiError> {
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
