// SPDX-License-Identifier: AGPL-3.0-only
//! Auth HTTP routes: register, login, refresh, connect-ticket, and logout.
//!
//! The durable mechanics live in [`crate::store`] and [`crate::auth`]; this
//! module is the thin REST skin over them, plus input validation, the bearer
//! extractor, and the error-to-status mapping.

use axum::extract::{DefaultBodyLimit, State};
use axum::http::StatusCode;
use axum::routing::{delete, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::Authed;
use crate::hub::Event;
use crate::store::{IssuedTokens, RefreshOutcome, RegisterError};

/// Auth payloads are a handful of short fields; cap the body well below any
/// realistic request so an oversized body is rejected before it is buffered.
const AUTH_BODY_LIMIT: usize = 4 * 1024;

/// The auth routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/auth/register", post(register))
        .route("/auth/login", post(login))
        .route("/auth/refresh", post(refresh))
        .route("/auth/ws-ticket", post(ws_ticket))
        .route("/auth/logout", post(logout))
        .route("/account", delete(delete_account))
        .layer(DefaultBodyLimit::max(AUTH_BODY_LIMIT))
}

// ---------------------------------------------------------------------------
// Wire types
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct RegisterRequest {
    username: String,
    display_name: String,
    password: String,
    device_name: String,
}

#[derive(Deserialize)]
struct LoginRequest {
    username: String,
    password: String,
    device_name: String,
}

#[derive(Deserialize)]
struct RefreshRequest {
    refresh_token: String,
}

#[derive(Serialize)]
struct TokenResponse {
    user_id: String,
    access_token: String,
    refresh_token: String,
    access_expires_at: i64,
}

#[derive(Serialize)]
struct TicketResponse {
    ticket: String,
    expires_at: i64,
}

fn token_response(tokens: &IssuedTokens) -> TokenResponse {
    TokenResponse {
        user_id: tokens.user_id.to_string(),
        access_token: tokens.access_token.clone(),
        refresh_token: tokens.refresh_token.clone(),
        access_expires_at: tokens.access_expires_at,
    }
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

// TODO(phase 2): gate registration behind invite redemption or an admin
// bootstrap once the invite flow exists; it is open now for server-core work.
async fn register(
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> Result<Json<TokenResponse>, ApiError> {
    validate_username(&req.username)?;
    validate_password(&req.password)?;
    validate_label(&req.display_name, "display_name must be 1 to 64 characters")?;
    validate_label(&req.device_name, "device_name must be 1 to 64 characters")?;

    let hash = state.auth.hash_password(req.password).await?;
    let account = match state
        .store
        .create_account(&req.username, &req.display_name, &hash)
        .await
    {
        Ok(account) => account,
        Err(RegisterError::UsernameTaken) => {
            return Err(ApiError::Conflict("username is already taken"));
        }
        Err(RegisterError::Internal(err)) => return Err(err.into()),
    };
    let tokens = state
        .store
        .open_session(account.id, &req.device_name)
        .await?;
    Ok(Json(token_response(&tokens)))
}

async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> Result<Json<TokenResponse>, ApiError> {
    validate_username(&req.username)?;
    validate_password(&req.password)?;
    validate_label(&req.device_name, "device_name must be 1 to 64 characters")?;

    let credentials = state.store.find_credentials(&req.username).await?;
    let verified = match &credentials {
        Some((_, hash)) => {
            state
                .auth
                .verify_password(req.password, hash.clone())
                .await?
        }
        // Spend a comparable amount of time so a missing account is not
        // distinguishable from a wrong password by response latency.
        None => {
            state.auth.verify_decoy().await;
            false
        }
    };

    let Some((user_id, _)) = credentials else {
        return Err(ApiError::Unauthorized);
    };
    if !verified {
        return Err(ApiError::Unauthorized);
    }

    let tokens = state.store.open_session(user_id, &req.device_name).await?;
    Ok(Json(token_response(&tokens)))
}

async fn refresh(
    State(state): State<AppState>,
    Json(req): Json<RefreshRequest>,
) -> Result<Json<TokenResponse>, ApiError> {
    match state.store.rotate_refresh(&req.refresh_token).await? {
        RefreshOutcome::Rotated(tokens) => Ok(Json(token_response(&tokens))),
        // A benign miss and a detected replay look identical to the client: the
        // only move either way is to log in again.
        RefreshOutcome::Denied | RefreshOutcome::Reused => Err(ApiError::Unauthorized),
    }
}

async fn ws_ticket(
    Authed(ctx): Authed,
    State(state): State<AppState>,
) -> Result<Json<TicketResponse>, ApiError> {
    let (ticket, expires_at) = state.store.mint_ws_ticket(&ctx).await?;
    Ok(Json(TicketResponse { ticket, expires_at }))
}

async fn logout(
    Authed(ctx): Authed,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    state.store.revoke_session(ctx.session_id).await?;
    // Drop any live WebSocket on this session at once, so revocation is instant
    // over the socket too, not just for the next REST call.
    state.hub.publish(Event::SessionRevoked(ctx.session_id));
    Ok(StatusCode::NO_CONTENT)
}

/// Deletes the caller's own account: purge personal data, anonymize authored
/// content, tombstone the user, and revoke every session (closing live sockets).
async fn delete_account(
    Authed(ctx): Authed,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    let revoked = state.store.delete_account(ctx.user_id).await?;
    for session_id in revoked {
        state.hub.publish(Event::SessionRevoked(session_id));
    }
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

fn validate_username(username: &str) -> Result<(), ApiError> {
    let len = username.chars().count();
    if !(1..=32).contains(&len) {
        return Err(ApiError::BadRequest("username must be 1 to 32 characters"));
    }
    let allowed = username
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-'));
    if !allowed {
        return Err(ApiError::BadRequest(
            "username may contain only letters, digits, and _ . -",
        ));
    }
    Ok(())
}

fn validate_password(password: &str) -> Result<(), ApiError> {
    let len = password.chars().count();
    if !(8..=1024).contains(&len) {
        return Err(ApiError::BadRequest(
            "password must be 8 to 1024 characters",
        ));
    }
    Ok(())
}

fn validate_label(value: &str, message: &'static str) -> Result<(), ApiError> {
    let len = value.chars().count();
    if !(1..=64).contains(&len) {
        return Err(ApiError::BadRequest(message));
    }
    if value.trim().is_empty() {
        return Err(ApiError::BadRequest("name must not be blank"));
    }
    if value.chars().any(is_disallowed_label_char) {
        return Err(ApiError::BadRequest(
            "name must not contain control or text-direction characters",
        ));
    }
    Ok(())
}

/// Rejects control (Cc) characters and the bidi and zero-width format characters
/// used to spoof how a name renders to other members.
fn is_disallowed_label_char(c: char) -> bool {
    c.is_control()
        || matches!(c,
            '\u{200B}'..='\u{200F}'   // zero-width space and joiners, LRM, RLM
            | '\u{202A}'..='\u{202E}' // bidi embeddings and overrides
            | '\u{2060}'              // word joiner
            | '\u{2066}'..='\u{2069}' // bidi isolates
            | '\u{FEFF}'              // zero-width no-break space / BOM
        )
}
