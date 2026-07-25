// SPDX-License-Identifier: AGPL-3.0-only
//! Admin-issued password reset: the self-hosted account recovery path chosen
//! in place of email. An administrator issues a one-time code for a locked-out
//! account; whoever holds it spends it once, here, to set a new password.
//!
//! Consuming a code revokes every live session on the account and closes any
//! open WebSocket on them, the same as logout and account deletion do,
//! because the point of this path is recovering an account that may be
//! compromised, not just changing its password out from under a session an
//! attacker still holds. Issuing and consuming are deliberately two different
//! trust levels: issuing needs ADMINISTRATOR, consuming needs nothing but the
//! code itself, since the person redeeming it is, by definition, someone who
//! cannot sign in right now.

use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::post;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::auth::validate_password;
use super::error::ApiError;
use super::extract::{Authed, PASSWORD, RateLimited, enforce};
use super::messages::parse_uuid;
use crate::hub::Event;
use crate::ids::UserId;
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::{ConsumeResetError, IssueResetError};

const BODY_LIMIT: usize = 4 * 1024;

/// The recovery routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/admin/users/{user_id}/reset-code", post(issue))
        .route("/auth/reset", post(reset))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

#[derive(Serialize)]
struct ResetCodeIssued {
    code: String,
    expires_at: i64,
}

#[derive(Deserialize)]
struct ResetRequest {
    code: String,
    new_password: String,
}

/// Issues a one-time reset code for another account. Requires ADMINISTRATOR.
async fn issue(
    Authed(ctx): Authed,
    parts: Parts,
    Path(user_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Json<ResetCodeIssued>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    if !state
        .store
        .base_permissions(ctx.user_id)
        .await?
        .contains(Permissions::ADMINISTRATOR)
    {
        return Err(ApiError::Forbidden);
    }

    let user_id = UserId(parse_uuid(&user_id)?);
    match state.store.issue_reset_code(ctx.user_id, user_id).await {
        Ok((code, expires_at)) => Ok(Json(ResetCodeIssued { code, expires_at })),
        Err(IssueResetError::NoSuchUser) => Err(ApiError::NotFound("user not found")),
        Err(IssueResetError::Internal(e)) => Err(e.into()),
    }
}

/// Spends a reset code, unauthenticated: the whole point is recovering an
/// account that cannot currently sign in. Rate limited on the same tight
/// budget as login, since a code is a guessable-length secret an attacker
/// would otherwise be free to grind.
async fn reset(
    _limited: RateLimited<PASSWORD>,
    State(state): State<AppState>,
    Json(req): Json<ResetRequest>,
) -> Result<StatusCode, ApiError> {
    validate_password(&req.new_password)?;
    let hash = state.auth.hash_password(req.new_password).await?;

    match state.store.consume_reset_code(&req.code, &hash).await {
        Ok(revoked) => {
            for session_id in revoked {
                state.hub.publish(Event::SessionRevoked(session_id));
            }
            Ok(StatusCode::NO_CONTENT)
        }
        // One answer whether the code was unknown, expired, or already used,
        // so this cannot be used to mine which codes are still live.
        Err(ConsumeResetError::Unusable) => {
            Err(ApiError::BadRequest("that reset code cannot be used"))
        }
        Err(ConsumeResetError::Internal(e)) => Err(e.into()),
    }
}
