// SPDX-License-Identifier: AGPL-3.0-only
//! Deployment-wide settings, read and written by an administrator.
//!
//! Reading is gated the same as writing rather than being open to any member.
//! Whether a Space is open to join is already public through `/version`, which
//! onboarding needs before an account exists; this route exists so the one
//! screen that can change it can also show what it is now, and gating both on
//! the same bit means nothing else about a deployment's configuration becomes
//! member-readable when a second setting lands here.

use axum::Router;
use axum::extract::{DefaultBodyLimit, State};
use axum::http::request::Parts;
use axum::routing::get;
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, Json, enforce};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::JoinPolicy;

const BODY_LIMIT: usize = 1024;

/// The Space settings routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/space/settings", get(read).patch(update))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

#[derive(Serialize, Deserialize)]
struct SpaceSettingsDto {
    join_policy: String,
}

async fn read(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
) -> Result<Json<SpaceSettingsDto>, ApiError> {
    // AuthedRead, not Write: this reads one config value, same as `update` writes one.
    enforce(&state, &parts, Some(&ctx), Class::AuthedRead)?;
    require_manage_server(&state, &ctx).await?;
    Ok(Json(SpaceSettingsDto {
        join_policy: state.store.join_policy().await?.as_str().to_owned(),
    }))
}

/// An unrecognised policy is refused rather than coerced, so a typo cannot
/// silently leave a Space on whichever branch the parser defaults to.
async fn update(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
    Json(body): Json<SpaceSettingsDto>,
) -> Result<Json<SpaceSettingsDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_server(&state, &ctx).await?;

    let policy = match body.join_policy.as_str() {
        "invite" => JoinPolicy::Invite,
        "open" => JoinPolicy::Open,
        _ => return Err(ApiError::BadRequest("join_policy must be invite or open")),
    };
    state.store.set_join_policy(policy).await?;
    Ok(Json(SpaceSettingsDto {
        join_policy: policy.as_str().to_owned(),
    }))
}

async fn require_manage_server(
    state: &AppState,
    ctx: &crate::store::SessionContext,
) -> Result<(), ApiError> {
    let permissions = state.store.base_permissions(ctx.user_id).await?;
    if !permissions.contains(Permissions::MANAGE_SERVER) {
        return Err(ApiError::Forbidden);
    }
    Ok(())
}
