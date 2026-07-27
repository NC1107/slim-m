// SPDX-License-Identifier: AGPL-3.0-only
//! Devices, blocking, and reporting.
//!
//! These exist partly because the app stores require them (an account must be
//! able to see its sessions, block someone, and report content), and partly
//! because they are the safety model the owner chose: human review of manual
//! reports, no automated scanning of anything.

use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::Authed;
use super::messages::parse_uuid;
use crate::hub::Event;
use crate::ids::{DeviceId, MessageId, UserId};
use crate::store::{Device, ReportError, ReportSubject};

const BODY_LIMIT: usize = 8 * 1024;
const MAX_REASON_CHARS: usize = 2000;

/// The device, block, and report routes.
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/devices", get(list_devices))
        .route("/devices/{device_id}", delete(remove_device))
        .route("/blocks", get(list_blocks))
        .route("/blocks/{user_id}", post(block).delete(unblock))
        .route("/reports", post(file_report))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

// --- Wire types ---

#[derive(Serialize)]
struct DeviceDto {
    id: String,
    name: String,
    created_at: i64,
    last_seen_at: Option<i64>,
    is_current: bool,
}

impl From<Device> for DeviceDto {
    fn from(device: Device) -> Self {
        Self {
            id: device.id.to_string(),
            name: device.name,
            created_at: device.created_at,
            last_seen_at: device.last_seen_at,
            is_current: device.is_current,
        }
    }
}

#[derive(Deserialize)]
struct ReportRequest {
    /// "message" or "user".
    subject_kind: String,
    subject_id: String,
    reason: String,
}

#[derive(Serialize)]
struct ReportFiled {
    id: String,
}

// --- Devices ---

async fn list_devices(
    Authed(ctx): Authed,
    State(state): State<AppState>,
) -> Result<Json<Vec<DeviceDto>>, ApiError> {
    let devices = state.store.list_devices(ctx.user_id, ctx.device_id).await?;
    Ok(Json(devices.into_iter().map(DeviceDto::from).collect()))
}

/// Signs a device out. Only ever your own: a device on someone else's account
/// is reported as missing, so this cannot be used to probe for or evict others.
async fn remove_device(
    Authed(ctx): Authed,
    Path(device_id): Path<String>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    let device_id = DeviceId(parse_uuid(&device_id)?);
    let revoked = state
        .store
        .remove_device(ctx.user_id, device_id)
        .await?
        .ok_or(ApiError::NotFound("device not found"))?;

    // Close any live socket on those sessions at once, the same as logout.
    for session_id in revoked {
        state.hub.publish(Event::SessionRevoked(session_id));
    }
    Ok(StatusCode::NO_CONTENT)
}

// --- Blocking ---

async fn list_blocks(
    Authed(ctx): Authed,
    State(state): State<AppState>,
) -> Result<Json<Vec<String>>, ApiError> {
    let blocked = state.store.blocked_users(ctx.user_id).await?;
    Ok(Json(blocked.into_iter().map(|id| id.to_string()).collect()))
}

/// Blocks someone. Idempotent, and silent by design: the blocked user is never
/// notified, because telling them turns blocking into a provocation.
async fn block(
    Authed(ctx): Authed,
    Path(user_id): Path<String>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    let target = UserId(parse_uuid(&user_id)?);
    if target == ctx.user_id {
        return Err(ApiError::BadRequest("you cannot block yourself"));
    }
    state.store.block_user(ctx.user_id, target).await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn unblock(
    Authed(ctx): Authed,
    Path(user_id): Path<String>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    let target = UserId(parse_uuid(&user_id)?);
    state.store.unblock_user(ctx.user_id, target).await?;
    Ok(StatusCode::NO_CONTENT)
}

// --- Reports ---

/// Files a report for a human to review. Nothing here inspects content
/// automatically; the whole point is that a person decides.
async fn file_report(
    Authed(ctx): Authed,
    State(state): State<AppState>,
    Json(req): Json<ReportRequest>,
) -> Result<Json<ReportFiled>, ApiError> {
    let reason = req.reason.trim();
    if reason.is_empty() {
        return Err(ApiError::BadRequest("a reason is required"));
    }
    if reason.chars().count() > MAX_REASON_CHARS {
        return Err(ApiError::BadRequest("that reason is too long"));
    }

    let id = parse_uuid(&req.subject_id)?;
    let subject = match req.subject_kind.as_str() {
        "message" => ReportSubject::Message(MessageId(id)),
        "user" => ReportSubject::User(UserId(id)),
        _ => return Err(ApiError::BadRequest("subject_kind must be message or user")),
    };

    // Reporting a message requires being able to see it, so the endpoint cannot
    // be used to confirm that a message exists in a channel you cannot read.
    if let ReportSubject::Message(message_id) = subject {
        let message = state.store.message(message_id).await?;
        let visible = match message {
            Some(ref m) => {
                state
                    .store
                    .has_permission(
                        ctx.user_id,
                        m.channel_id,
                        crate::permissions::Permissions::VIEW_CHANNEL,
                    )
                    .await?
            }
            None => false,
        };
        if !visible {
            return Err(ApiError::NotFound("that message was not found"));
        }
    }

    match state.store.file_report(ctx.user_id, subject, reason).await {
        Ok(id) => Ok(Json(ReportFiled { id: id.to_string() })),
        Err(ReportError::AlreadyOpen) => Err(ApiError::Conflict("you already reported that")),
        Err(ReportError::NotFound) => Err(ApiError::NotFound("that was not found")),
        Err(ReportError::Internal(e)) => Err(e.into()),
    }
}
