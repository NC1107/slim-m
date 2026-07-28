// SPDX-License-Identifier: AGPL-3.0-only
//! Push registration routes: register or replace the caller's own device's
//! push registration, drop it, and report the client's lifecycle state.
//!
//! Every handler here uses the device id from the authenticated session, never
//! one taken from the request body, so a device can never write another
//! device's registration; [`crate::store::Store::register_push`] and its
//! siblings re-check `user_id` too, so this holds even if that ever changes.

use axum::Router;
use axum::extract::{DefaultBodyLimit, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::put;
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use serde::Deserialize;

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, Json, enforce};
use crate::ratelimit::Class;

const BODY_LIMIT: usize = 4 * 1024;

/// X25519 public keys are exactly 32 bytes.
const PUBLIC_KEY_BYTES: usize = 32;
const MAX_TOKEN_CHARS: usize = 1024;
const MAX_LIFECYCLE_STATE_CHARS: usize = 32;

/// The push routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/push", put(register).delete(deregister))
        .route("/push/lifecycle", put(report_lifecycle))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

// --- Wire types ---

#[derive(Deserialize)]
struct RegisterRequest {
    /// "ios" or "android".
    platform: String,
    push_token: String,
    voip_push_token: Option<String>,
    /// The device's X25519 public key, base64-encoded (32 bytes decoded).
    push_public_key: String,
}

#[derive(Deserialize)]
struct LifecycleRequest {
    /// Free-form client lifecycle label, for example "foreground" or
    /// "background". Only "foreground" carries meaning to the server today;
    /// anything else is just not-foreground.
    state: String,
}

// --- Handlers ---

async fn register(
    Authed(ctx): Authed,
    parts: Parts,
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;

    if !matches!(req.platform.as_str(), "ios" | "android") {
        return Err(ApiError::BadRequest("platform must be ios or android"));
    }
    let push_token = validate_token(&req.push_token, "push_token")?;
    let voip_push_token = req
        .voip_push_token
        .as_deref()
        .map(|t| validate_token(t, "voip_push_token"))
        .transpose()?;
    let public_key = BASE64
        .decode(&req.push_public_key)
        .ok()
        .filter(|bytes| bytes.len() == PUBLIC_KEY_BYTES)
        .ok_or(ApiError::BadRequest(
            "push_public_key must be a base64-encoded 32-byte X25519 key",
        ))?;

    state
        .store
        .register_push(
            ctx.user_id,
            ctx.device_id,
            &req.platform,
            push_token,
            voip_push_token,
            &public_key,
        )
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn deregister(
    Authed(ctx): Authed,
    parts: Parts,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    state
        .store
        .deregister_push(ctx.user_id, ctx.device_id)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn report_lifecycle(
    Authed(ctx): Authed,
    parts: Parts,
    State(state): State<AppState>,
    Json(req): Json<LifecycleRequest>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let state_value = req.state.trim();
    if state_value.is_empty() || state_value.chars().count() > MAX_LIFECYCLE_STATE_CHARS {
        return Err(ApiError::BadRequest("state must be 1 to 32 characters"));
    }

    state
        .store
        .report_lifecycle(ctx.user_id, ctx.device_id, state_value)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

// --- Validation ---

fn validate_token<'a>(token: &'a str, field: &'static str) -> Result<&'a str, ApiError> {
    if token.is_empty() || token.chars().count() > MAX_TOKEN_CHARS {
        match field {
            "voip_push_token" => Err(ApiError::BadRequest(
                "voip_push_token must be 1 to 1024 characters",
            )),
            _ => Err(ApiError::BadRequest(
                "push_token must be 1 to 1024 characters",
            )),
        }
    } else {
        Ok(token)
    }
}
