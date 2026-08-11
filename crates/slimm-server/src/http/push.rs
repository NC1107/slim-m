// SPDX-License-Identifier: AGPL-3.0-only
//! Push registration routes: register or replace the caller's own device's
//! push registration, drop it, report the client's lifecycle state, and read
//! or set the caller's account-wide notification preference.
//!
//! Every device-scoped handler here (all but the last two) uses the device id
//! from the authenticated session, never one taken from the request body, so
//! a device can never write another device's registration;
//! [`crate::store::Store::register_push`] and its siblings re-check `user_id`
//! too, so this holds even if that ever changes. The notification preference
//! is deliberately not device-scoped: it decides whether *any* of the
//! caller's devices should buzz for a message, so it lives on the account,
//! not on the session's own device id.

use axum::Router;
use axum::extract::{DefaultBodyLimit, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{get, put};
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, AuthedLimited, Json, READ, enforce};
use crate::notifications::NotificationPreference;
use crate::ratelimit::Class;
use crate::store::PushRegistration;

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
        .route("/push/preference", get(get_preference).put(set_preference))
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
    /// Whether this device wants a preview of the message sealed inside its
    /// own envelope. Absent means no, so a client that predates this field
    /// keeps getting exactly the content-free envelope it was built for.
    ///
    /// Device-scoped, unlike the account-wide notification preference below:
    /// this decides what appears on one physical device's lock screen, so a
    /// personal phone and a shared tablet on the same account can answer
    /// differently. It never changes *whether* a device is woken, only what
    /// its own envelope carries, and the relay can read neither answer.
    #[serde(default)]
    include_content: bool,
}

#[derive(Deserialize)]
struct LifecycleRequest {
    /// Free-form client lifecycle label, for example "foreground" or
    /// "background". Only "foreground" carries meaning to the server today;
    /// anything else is just not-foreground.
    state: String,
}

#[derive(Deserialize, Serialize)]
struct NotificationPreferenceDto {
    preference: String,
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
            PushRegistration {
                platform: &req.platform,
                push_token,
                voip_push_token,
                push_public_key: &public_key,
                include_content: req.include_content,
            },
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

/// Reads the caller's own notification preference back, a genuine round trip
/// rather than a local echo: unlike `PATCH /presence`, nothing here needs a
/// batched, per-viewer-derived answer, so there is no reason this cannot
/// simply answer with the stored value.
async fn get_preference(
    AuthedLimited(ctx): AuthedLimited<READ>,
    State(state): State<AppState>,
) -> Result<Json<NotificationPreferenceDto>, ApiError> {
    let preference = state
        .store
        .notification_preference(ctx.user_id)
        .await?
        .ok_or(ApiError::Unauthorized)?;
    Ok(Json(NotificationPreferenceDto {
        preference: preference.as_str().to_owned(),
    }))
}

/// Sets the caller's own notification preference. Enforced where push
/// recipients are computed (`push::recipients::message_recipients`), before a
/// device is ever woken - never a filter a client applies to a push that has
/// already landed.
async fn set_preference(
    Authed(ctx): Authed,
    parts: Parts,
    State(state): State<AppState>,
    Json(req): Json<NotificationPreferenceDto>,
) -> Result<Json<NotificationPreferenceDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let preference = NotificationPreference::parse(&req.preference).ok_or(ApiError::BadRequest(
        "preference must be everything, mentions, or nothing",
    ))?;

    if !state
        .store
        .set_notification_preference(ctx.user_id, preference)
        .await?
    {
        return Err(ApiError::Unauthorized);
    }
    Ok(Json(NotificationPreferenceDto {
        preference: preference.as_str().to_owned(),
    }))
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
