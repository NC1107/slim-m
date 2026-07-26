// SPDX-License-Identifier: AGPL-3.0-only
//! User profile routes: the caller's own account (`/me`), public profiles
//! (`/users`), and the deployment's member list (`/members`).
//!
//! Every profile returned here is the narrow public shape only: id,
//! username, display name, and creation time. Nothing from the auth tables
//! is reachable through any of these routes, and a deleted or anonymized
//! account answers exactly like an id that was never used, so none of them
//! can be used to confirm someone deleted their account.

use std::collections::HashMap;

use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::response::Response;
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::attachments::serve;
use super::auth::validate_label;
use super::error::ApiError;
use super::extract::{Authed, enforce};
use super::messages::parse_uuid;
use crate::ids::UserId;
use crate::media;
use crate::ratelimit::Class;
use crate::store::{Store, User};

const BODY_LIMIT: usize = 4 * 1024;

/// Largest avatar a user may upload. Tighter than the general attachment
/// ceiling and not operator-configurable: an avatar is always a small,
/// single image, never a document or a large photo, so there is nothing here
/// a self-host operator would need to tune.
const AVATAR_MAX_BYTES: u64 = 2 * 1024 * 1024;

/// Most ids `GET /users` may be asked about in one request.
const MAX_USER_BATCH: usize = 100;
/// Default and maximum page sizes for the member list.
const MEMBERS_DEFAULT_LIMIT: i64 = 50;
const MEMBERS_MAX_LIMIT: i64 = 200;

/// The user profile routes, mounted by [`super::router`].
///
/// Two sub-routers rather than one: `/me/avatar` needs a body-size ceiling
/// large enough for an image, while every other route here (all plain JSON
/// or bodyless) is deliberately kept to [`BODY_LIMIT`]. Merging them after
/// building each with its own `.layer(...)` keeps the small ceiling for the
/// routes that never needed a bigger one.
pub fn routes() -> Router<AppState> {
    let profile = Router::new()
        .route("/me", get(get_me).patch(update_me))
        .route("/users", get(list_users))
        .route("/users/{user_id}", get(get_user))
        .route("/users/{user_id}/avatar", get(get_avatar))
        .route("/members", get(list_members))
        .layer(DefaultBodyLimit::max(BODY_LIMIT));

    let avatar_upload = Router::new()
        .route("/me/avatar", post(upload_avatar).delete(delete_avatar))
        .layer(DefaultBodyLimit::max(AVATAR_MAX_BYTES as usize));

    profile.merge(avatar_upload)
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
    /// When this user's avatar was last set, or `null` for no avatar. Not a
    /// fetchable value on its own - a client appends it as a cache-busting
    /// query parameter on `GET /users/{userId}/avatar`, which ignores the
    /// query string itself and just serves whatever is currently stored.
    avatar_updated_at: Option<i64>,
    /// Role names this member holds, for a client to render a badge (e.g.
    /// "Op") beside them. Excludes `@everyone`: every member holds that one,
    /// so including it would put a meaningless badge on every row. Empty
    /// rather than omitted for a member with nothing beyond it - the same
    /// "always present, empty means none" convention `MessageDto::reactions`
    /// already follows. Deliberately no colour: badges use the design
    /// system's accent, not a per-role one.
    roles: Vec<String>,
}

/// Builds one profile DTO, including this user's non-`@everyone` role names.
/// A single extra query beyond the profile fetch itself; see [`to_dtos`] for
/// the batched form a page of users needs instead of paying this per row.
async fn to_dto(store: &Store, user: User) -> anyhow::Result<UserDto> {
    Ok(to_dtos(store, vec![user]).await?.remove(0))
}

/// Builds a page of profile DTOs, batching the roles lookup into one query
/// regardless of how many users are being described at once - the shape
/// [`Store::roles_for_users`] follows from [`Store::reactions_for_messages`],
/// which is what keeps `GET /members` (paginated up to 200) from paying one
/// query per row.
async fn to_dtos(store: &Store, users: Vec<User>) -> anyhow::Result<Vec<UserDto>> {
    let ids: Vec<UserId> = users.iter().map(|u| u.id).collect();
    let role_names: HashMap<UserId, Vec<String>> =
        store.roles_for_users(&ids).await?.into_iter().collect();
    Ok(users
        .into_iter()
        .map(|user| UserDto {
            id: user.id.to_string(),
            username: user.username,
            display_name: user.display_name,
            created_at: user.created_at,
            avatar_updated_at: user.avatar_updated_at,
            roles: role_names.get(&user.id).cloned().unwrap_or_default(),
        })
        .collect())
}

#[derive(Serialize)]
struct MeDto {
    id: String,
    username: String,
    display_name: String,
    created_at: i64,
    avatar_updated_at: Option<i64>,
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
        avatar_updated_at: user.avatar_updated_at,
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
    Ok(Json(to_dto(&state.store, user).await?))
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
    Ok(Json(to_dto(&state.store, user).await?))
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
    Ok(Json(to_dtos(&state.store, users).await?))
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
    Ok(Json(to_dtos(&state.store, members).await?))
}

// ---------------------------------------------------------------------------
// Handlers: avatars
// ---------------------------------------------------------------------------

/// Uploads (or replaces) the caller's avatar. Deliberately not an attachment:
/// one mutable image per user, keyed by user id rather than content hash, and
/// replaced wholesale rather than accumulated - see migration 0013.
///
/// The file is written before the database row is updated, so a crash
/// between the two steps leaves the old row pointing at bytes that were just
/// overwritten (self-heals on the next successful upload) rather than a row
/// that promises an avatar no file backs.
async fn upload_avatar(
    Authed(ctx): Authed,
    parts: Parts,
    State(state): State<AppState>,
    body: Bytes,
) -> Result<Json<UserDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Upload)?;

    if body.is_empty() {
        return Err(ApiError::BadRequest("avatar is empty"));
    }
    if body.len() as u64 > AVATAR_MAX_BYTES {
        return Err(ApiError::BadRequest("avatar is too large"));
    }
    // An avatar is always a picture: sniffed against the same allowlist as a
    // message attachment, but only the inline (image) entries qualify - a
    // PDF is a valid attachment and not a valid avatar. The content type
    // itself is not stored here; `get_avatar` re-sniffs it from disk.
    let is_image = media::sniff_content_type(&body).is_some_and(media::is_inline);
    if !is_image {
        return Err(ApiError::BadRequest("unsupported avatar type"));
    }

    let user_id = ctx.user_id.to_string();
    state
        .media
        .write_avatar(&user_id, body.to_vec())
        .await
        .map_err(|err| {
            tracing::error!(error = %err, "failed to write an uploaded avatar");
            ApiError::Internal
        })?;

    let user = state
        .store
        .set_avatar_updated(ctx.user_id)
        .await?
        .ok_or(ApiError::Unauthorized)?;
    Ok(Json(to_dto(&state.store, user).await?))
}

/// Removes the caller's avatar.
async fn delete_avatar(
    Authed(ctx): Authed,
    parts: Parts,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    state.store.clear_avatar(ctx.user_id).await?;
    if let Err(err) = state.media.delete_avatar(&ctx.user_id.to_string()).await {
        tracing::warn!(error = %err, "failed to delete a cleared avatar file");
    }
    Ok(StatusCode::NO_CONTENT)
}

/// Fetches a user's avatar bytes. Any authenticated caller may fetch any
/// live user's avatar: it is a public profile picture, gated the same way
/// the rest of a `UserProfile` is (authentication only, no channel
/// permission), not a message attachment.
async fn get_avatar(
    Authed(_ctx): Authed,
    Path(user_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Response, ApiError> {
    let user_id = UserId(parse_uuid(&user_id)?);
    let user = state
        .store
        .user_profile(user_id)
        .await?
        .ok_or(ApiError::NotFound("user not found"))?;
    if user.avatar_updated_at.is_none() {
        return Err(ApiError::NotFound("user has no avatar"));
    }

    let bytes = state
        .media
        .read_avatar(&user_id.to_string())
        .await
        .map_err(|err| {
            tracing::error!(error = %err, "failed to read a stored avatar");
            ApiError::Internal
        })?;
    // Re-sniffed from the bytes on disk rather than trusting a stored content
    // type: the file is the only thing that can never disagree with itself.
    let content_type = media::sniff_content_type(&bytes).ok_or_else(|| {
        tracing::error!("stored avatar bytes no longer match the upload allowlist");
        ApiError::Internal
    })?;
    Ok(serve(bytes, content_type, "avatar"))
}
