// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The dynamic half of the roles surface: module-declared permissions,
//! registered by `http::dock`'s install handler, appear here as grantable
//! rows alongside `http::roles`'s core bitmask, and a role's grant of one
//! round-trips the same way a core permission does. See
//! docs/decisions/0021-modules-and-the-dock.md.
//!
//! Gated on MANAGE_ROLES, the same bit as every other mutation in
//! `http::roles` - granting a module permission is a role-management act,
//! not a Dock one, so it stays on that surface's own gate rather than
//! `MANAGE_SERVER`. Kept in its own file purely for `roles.rs`'s file
//! budget, the same reasoning `messages_bulk`/`messages_bulk_window` split
//! on.

use axum::Router;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{get, put};
use serde::Serialize;

use super::AppState;
use super::error::ApiError;
use super::extract::{AUTHED_READ, Authed, AuthedLimited, Json, enforce};
use super::messages::parse_uuid;
use crate::hub::Event;
use crate::ids::{RoleId, UserId};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::{GrantModulePermissionError, GrantedModulePermission, ModulePermission};

const BODY_LIMIT: usize = 256;

/// The module-permission routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/roles/module-permissions", get(list_catalog))
        .route("/roles/{role_id}/module-permissions", get(list_role_grants))
        .route(
            "/roles/{role_id}/module-permissions/{module_id}/{perm_key}",
            put(grant).delete(revoke),
        )
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

#[derive(Serialize)]
struct ModulePermissionDto {
    module_id: String,
    module_name: String,
    perm_key: String,
    name: String,
    description: String,
}

impl From<ModulePermission> for ModulePermissionDto {
    fn from(p: ModulePermission) -> Self {
        Self {
            module_id: p.module_id,
            module_name: p.module_name,
            perm_key: p.perm_key,
            name: p.name,
            description: p.description,
        }
    }
}

#[derive(Serialize)]
struct GrantedModulePermissionDto {
    module_id: String,
    perm_key: String,
}

impl From<GrantedModulePermission> for GrantedModulePermissionDto {
    fn from(g: GrantedModulePermission) -> Self {
        Self {
            module_id: g.module_id,
            perm_key: g.perm_key,
        }
    }
}

/// Every module permission any installed module currently declares - the
/// full catalog of module-scoped grantable rows, independent of any one
/// role.
async fn list_catalog(
    AuthedLimited(ctx): AuthedLimited<AUTHED_READ>,
    State(state): State<AppState>,
) -> Result<Json<Vec<ModulePermissionDto>>, ApiError> {
    require_manage_roles(&state, ctx.user_id).await?;
    let rows = state.store.list_module_permissions().await?;
    Ok(Json(
        rows.into_iter().map(ModulePermissionDto::from).collect(),
    ))
}

async fn list_role_grants(
    AuthedLimited(ctx): AuthedLimited<AUTHED_READ>,
    State(state): State<AppState>,
    Path(role_id): Path<String>,
) -> Result<Json<Vec<GrantedModulePermissionDto>>, ApiError> {
    require_manage_roles(&state, ctx.user_id).await?;
    let role_id = RoleId(parse_uuid(&role_id)?);
    let rows = state.store.role_module_permissions(role_id).await?;
    Ok(Json(
        rows.into_iter()
            .map(GrantedModulePermissionDto::from)
            .collect(),
    ))
}

async fn grant(
    Authed(ctx): Authed,
    parts: Parts,
    Path((role_id, module_id, perm_key)): Path<(String, String, String)>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_roles(&state, ctx.user_id).await?;
    let role_id = RoleId(parse_uuid(&role_id)?);
    state
        .store
        .role(role_id)
        .await?
        .ok_or(ApiError::NotFound("role not found"))?;

    match state
        .store
        .grant_module_permission(role_id, &module_id, &perm_key)
        .await
    {
        Ok(()) => {
            state.hub.publish(Event::RoleChanged { role_id });
            Ok(StatusCode::NO_CONTENT)
        }
        Err(GrantModulePermissionError::UnknownPermission) => Err(ApiError::NotFound(
            "no installed module declares that permission",
        )),
        Err(GrantModulePermissionError::Internal(e)) => Err(e.into()),
    }
}

async fn revoke(
    Authed(ctx): Authed,
    parts: Parts,
    Path((role_id, module_id, perm_key)): Path<(String, String, String)>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_roles(&state, ctx.user_id).await?;
    let role_id = RoleId(parse_uuid(&role_id)?);

    state
        .store
        .revoke_module_permission(role_id, &module_id, &perm_key)
        .await?;
    state.hub.publish(Event::RoleChanged { role_id });
    Ok(StatusCode::NO_CONTENT)
}

async fn require_manage_roles(state: &AppState, user_id: UserId) -> Result<(), ApiError> {
    let permissions = state.store.base_permissions(user_id).await?;
    if !permissions.contains(Permissions::MANAGE_ROLES) {
        return Err(ApiError::Forbidden);
    }
    Ok(())
}
