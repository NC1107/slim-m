// SPDX-License-Identifier: AGPL-3.0-only
//! User profile routes: the caller's own account (`/me`), public profiles
//! (`/users`), and the deployment's member list (`/members`).
//!
//! Every profile returned here is the narrow public shape only: id,
//! username, display name, and creation time. Nothing from the auth tables
//! is reachable through any of these routes, and a deleted or anonymized
//! account answers exactly like an id that was never used, so none of them
//! can be used to confirm someone deleted their account.

use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::request::Parts;
use axum::routing::get;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::auth::validate_label;
use super::error::ApiError;
use super::extract::{Authed, enforce};
use super::messages::parse_uuid;
use crate::ids::UserId;
use crate::ratelimit::Class;
use crate::store::User;

const BODY_LIMIT: usize = 4 * 1024;

/// Most ids `GET /users` may be asked about in one request.
const MAX_USER_BATCH: usize = 100;
/// Default and maximum page sizes for the member list.
const MEMBERS_DEFAULT_LIMIT: i64 = 50;
const MEMBERS_MAX_LIMIT: i64 = 200;

/// The user profile routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/me", get(get_me).patch(update_me))
        .route("/users", get(list_users))
        .route("/users/{user_id}", get(get_user))
        .route("/members", get(list_members))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

// ---------------------------------------------------------------------------
// Wire types
// ---------------------------------------------------------------------------

#[derive(Serialize)]
struct UserDto {
    id: String,
    username: String,
    display_name: String,
    created_at: i64,
}

impl From<User> for UserDto {
    fn from(user: User) -> Self {
        Self {
            id: user.id.to_string(),
            username: user.username,
            display_name: user.display_name,
            created_at: user.created_at,
        }
    }
}

#[derive(Serialize)]
struct MeDto {
    id: String,
    username: String,
    display_name: String,
    created_at: i64,
    /// The caller's base, deployment-level permission bitmask: the
    /// `@everyone` role plus every role they hold, ignoring any per-channel
    /// overwrite. A client uses this to decide which actions to show, but
    /// that is a UI nicety only; every write is re-authorized server-side
    /// from scratch regardless of what a client chose to display.
    permissions: i64,
}

#[derive(Deserialize)]
struct UpdateMeRequest {
    display_name: String,
    // Username is deliberately not a field here: it backs the live
    // per-account uniqueness index (`users_username_live`), and changing it
    // needs a dedicated flow that can handle the resulting collision. That is
    // why it is absent rather than accepted and quietly ignored.
}

#[derive(Deserialize)]
struct ListUsersParams {
    ids: Option<String>,
}

#[derive(Deserialize)]
struct ListMembersParams {
    after: Option<String>,
    limit: Option<i64>,
}

// ---------------------------------------------------------------------------
// Handlers: /me
// ---------------------------------------------------------------------------

async fn get_me(
    Authed(ctx): Authed,
    State(state): State<AppState>,
) -> Result<Json<MeDto>, ApiError> {
    let user = state
        .store
        .user_profile(ctx.user_id)
        .await?
        .ok_or(ApiError::Unauthorized)?;
    let permissions = state.store.base_permissions(ctx.user_id).await?;
    Ok(Json(MeDto {
        id: user.id.to_string(),
        username: user.username,
        display_name: user.display_name,
        created_at: user.created_at,
        permissions: permissions.bits(),
    }))
}

async fn update_me(
    Authed(ctx): Authed,
    parts: Parts,
    State(state): State<AppState>,
    Json(req): Json<UpdateMeRequest>,
) -> Result<Json<UserDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    validate_label(&req.display_name, "display_name must be 1 to 64 characters")?;

    let user = state
        .store
        .update_display_name(ctx.user_id, &req.display_name)
        .await?
        .ok_or(ApiError::Unauthorized)?;
    Ok(Json(user.into()))
}

// ---------------------------------------------------------------------------
// Handlers: /users
// ---------------------------------------------------------------------------

async fn get_user(
    Authed(_ctx): Authed,
    Path(user_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<UserDto>, ApiError> {
    let user_id = UserId(parse_uuid(&user_id)?);
    let user = state
        .store
        .user_profile(user_id)
        .await?
        .ok_or(ApiError::NotFound("user not found"))?;
    Ok(Json(user.into()))
}

/// Batch profile lookup. A missing id (never existed, or deleted) is simply
/// absent from the result rather than reported, so the response may be
/// shorter than the request; the caller matches by id.
async fn list_users(
    Authed(_ctx): Authed,
    Query(params): Query<ListUsersParams>,
    State(state): State<AppState>,
) -> Result<Json<Vec<UserDto>>, ApiError> {
    let raw = params.ids.unwrap_or_default();
    let mut ids = Vec::new();
    for part in raw.split(',') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        if ids.len() >= MAX_USER_BATCH {
            return Err(ApiError::BadRequest("too many ids requested"));
        }
        ids.push(UserId(parse_uuid(part)?));
    }

    let users = state.store.user_profiles(&ids).await?;
    Ok(Json(users.into_iter().map(UserDto::from).collect()))
}

// ---------------------------------------------------------------------------
// Handlers: /members
// ---------------------------------------------------------------------------

/// Lists the deployment's live members for a member list. Any authenticated
/// caller may read it: a member list is deployment-wide, not scoped to any
/// one channel, so there is no channel permission to check it against.
async fn list_members(
    Authed(_ctx): Authed,
    Query(params): Query<ListMembersParams>,
    State(state): State<AppState>,
) -> Result<Json<Vec<UserDto>>, ApiError> {
    let after = params
        .after
        .as_deref()
        .map(parse_uuid)
        .transpose()?
        .map(UserId);
    let limit = params
        .limit
        .unwrap_or(MEMBERS_DEFAULT_LIMIT)
        .clamp(1, MEMBERS_MAX_LIMIT);

    let members = state.store.list_members(after, limit).await?;
    Ok(Json(members.into_iter().map(UserDto::from).collect()))
}
