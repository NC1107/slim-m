// SPDX-License-Identifier: AGPL-3.0-only
//! Presence routes: read other users' current status, and set the caller's
//! own visibility preference.
//!
//! Deployment-wide like the member list, not scoped to a channel: presence
//! has never depended on a shared channel, only a shared deployment. Every
//! status returned here goes through [`crate::presence::status_for`], the
//! same function the WebSocket broadcast in [`super::ws`] uses, so a user who
//! chose to appear offline reads as offline through both surfaces or neither.

use axum::Router;
use axum::extract::{DefaultBodyLimit, State};
use axum::http::request::Parts;
use axum::routing::get;
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, Json, Query, enforce};
use super::messages::parse_uuid;
use crate::hub::Event;
use crate::ids::UserId;
use crate::presence::{self, Visibility};
use crate::ratelimit::Class;

const BODY_LIMIT: usize = 1024;

/// Most ids `GET /presence` may be asked about in one request, matching the
/// batch ceiling `GET /users` already uses.
const MAX_BATCH: usize = 100;

/// The presence routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/presence", get(list).patch(set_visibility))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

// --- Wire types ---

#[derive(Serialize)]
struct PresenceDto {
    user_id: String,
    status: String,
}

#[derive(Deserialize)]
struct ListPresenceParams {
    ids: Option<String>,
}

#[derive(Deserialize, Serialize)]
struct VisibilityDto {
    visibility: String,
}

// --- Handlers ---

/// Batch presence lookup. An id with nothing live to report (never existed,
/// or deleted) is simply absent from the result, the same contract
/// [`super::users::list_users`] has for a profile.
async fn list(
    Authed(ctx): Authed,
    Query(params): Query<ListPresenceParams>,
    State(state): State<AppState>,
) -> Result<Json<Vec<PresenceDto>>, ApiError> {
    let raw = params.ids.unwrap_or_default();
    let mut ids = Vec::new();
    for part in raw.split(',') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        if ids.len() >= MAX_BATCH {
            return Err(ApiError::BadRequest("too many ids requested"));
        }
        ids.push(UserId(parse_uuid(part)?));
    }

    let mut dtos = Vec::with_capacity(ids.len());
    for target in ids {
        let Some(visibility) = state.store.presence_visibility(target).await? else {
            continue;
        };
        let tracker = state.hub.presence();
        let status = presence::status_for(
            ctx.user_id,
            target,
            visibility,
            tracker.is_connected(target),
            tracker.is_idle(target),
        );
        dtos.push(PresenceDto {
            user_id: target.to_string(),
            status: status.as_str().to_owned(),
        });
    }
    Ok(Json(dtos))
}

/// Sets the caller's durable visibility preference and tells every live
/// viewer at once, rather than waiting for their next reconnect: toggling
/// appear-offline is only a real privacy control if it takes effect
/// immediately.
async fn set_visibility(
    Authed(ctx): Authed,
    parts: Parts,
    State(state): State<AppState>,
    Json(req): Json<VisibilityDto>,
) -> Result<Json<VisibilityDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let visibility = Visibility::parse(&req.visibility).ok_or(ApiError::BadRequest(
        "visibility must be online, away, dnd, or hidden",
    ))?;

    if !state
        .store
        .set_presence_visibility(ctx.user_id, visibility)
        .await?
    {
        return Err(ApiError::Unauthorized);
    }
    state.hub.publish(Event::PresenceChanged(ctx.user_id));

    Ok(Json(VisibilityDto {
        visibility: visibility.as_str().to_owned(),
    }))
}
