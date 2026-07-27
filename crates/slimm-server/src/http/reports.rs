// SPDX-License-Identifier: AGPL-3.0-only
//! Report triage: the moderation queue over what [`super::safety::file_report`]
//! intakes.
//!
//! Gated on MANAGE_MESSAGES at the deployment level. A report carries a
//! snapshot of the reported content (see [`crate::store::Report`]), so this
//! surface must never answer to anyone below that bar; every handler here
//! checks it before touching the store, the same as the rest of this file's
//! sibling admin surfaces do.

use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{get, patch};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, enforce};
use super::messages::parse_uuid;
use crate::ids::UserId;
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::Report;

const BODY_LIMIT: usize = 4 * 1024;

/// The report triage routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/reports", get(list))
        .route("/reports/{report_id}", patch(resolve))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

#[derive(Serialize)]
struct ReportDto {
    id: String,
    /// Null once the reporter's account has been anonymized.
    reporter_id: Option<String>,
    subject_kind: String,
    subject_id: String,
    channel_id: Option<String>,
    reason: String,
    /// The reported content as it stood at filing time; the author may have
    /// since edited or deleted it. Absent from every route below the
    /// MANAGE_MESSAGES bar.
    snapshot: Option<String>,
    created_at: i64,
}

impl From<Report> for ReportDto {
    fn from(report: Report) -> Self {
        Self {
            id: report.id.to_string(),
            reporter_id: report.reporter_id.map(|id| id.to_string()),
            subject_kind: report.subject_kind,
            subject_id: report.subject_id.to_string(),
            channel_id: report.channel_id.map(|id| id.to_string()),
            reason: report.reason,
            snapshot: report.snapshot,
            created_at: report.created_at,
        }
    }
}

#[derive(Deserialize)]
struct ResolveReportRequest {
    /// "resolved" or "dismissed".
    resolution: String,
}

/// Lists the open moderation queue, oldest first.
///
/// A report carries the reported content verbatim, so the queue is filtered
/// per channel rather than shown wholesale. `base_permissions` ignores channel
/// overwrites by construction, so a moderator explicitly denied
/// MANAGE_MESSAGES in one channel would otherwise still read every message
/// reported there. Reports with no channel are deployment-wide (a report about
/// a user rather than a message) and stay on the base check alone.
async fn list(
    Authed(ctx): Authed,
    State(state): State<AppState>,
) -> Result<Json<Vec<ReportDto>>, ApiError> {
    require_manage_messages(&state, ctx.user_id).await?;
    let reports = state.store.list_open_reports().await?;

    // Re-checked per channel, not just deployment-wide; see the note on this
    // function.
    let mut visible = Vec::with_capacity(reports.len());
    for report in reports {
        let allowed = match report.channel_id {
            None => true,
            Some(channel_id) => state
                .store
                .has_permission(ctx.user_id, channel_id, Permissions::MANAGE_MESSAGES)
                .await
                .unwrap_or(false),
        };
        if allowed {
            visible.push(ReportDto::from(report));
        }
    }
    Ok(Json(visible))
}

/// Closes a report as resolved or dismissed. The claim is a conditional
/// `UPDATE` in the store, so two moderators racing the same report cannot
/// both win it; whichever loses sees the report as already gone.
///
/// Gated per channel exactly as [`list`] is. Without that, a moderator denied
/// MANAGE_MESSAGES in one channel could not read its reports but could still
/// dismiss them, quietly emptying the queue for the very channel they were
/// deliberately excluded from. A report they may not act on is reported as
/// missing rather than forbidden, so the endpoint does not confirm one exists.
async fn resolve(
    Authed(ctx): Authed,
    parts: Parts,
    Path(report_id): Path<String>,
    State(state): State<AppState>,
    Json(req): Json<ResolveReportRequest>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_messages(&state, ctx.user_id).await?;
    let report_id = parse_uuid(&report_id)?;

    let resolution = match req.resolution.as_str() {
        "resolved" | "dismissed" => req.resolution.as_str(),
        _ => {
            return Err(ApiError::BadRequest(
                "resolution must be resolved or dismissed",
            ));
        }
    };

    let Some(channel_id) = state.store.open_report_channel(report_id).await? else {
        return Err(ApiError::NotFound("report not found"));
    };
    if let Some(channel_id) = channel_id
        && !state
            .store
            .has_permission(ctx.user_id, channel_id, Permissions::MANAGE_MESSAGES)
            .await?
    {
        return Err(ApiError::NotFound("report not found"));
    }

    let closed = state
        .store
        .resolve_report(report_id, ctx.user_id, resolution)
        .await?;
    if !closed {
        return Err(ApiError::NotFound("report not found"));
    }
    Ok(StatusCode::NO_CONTENT)
}

async fn require_manage_messages(state: &AppState, user_id: UserId) -> Result<(), ApiError> {
    if !state
        .store
        .base_permissions(user_id)
        .await?
        .contains(Permissions::MANAGE_MESSAGES)
    {
        return Err(ApiError::Forbidden);
    }
    Ok(())
}
