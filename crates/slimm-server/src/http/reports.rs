// SPDX-License-Identifier: AGPL-3.0-only
//! Report triage: the moderation queue over what [`super::safety::file_report`]
//! intakes.
//!
//! Gated on MANAGE_MESSAGES at the deployment level. A report carries a
//! snapshot of the reported content (see [`crate::store::Report`]), so this
//! surface must never answer to anyone below that bar; every handler here
//! checks it before touching the store, the same as the rest of this file's
//! sibling admin surfaces do.

use axum::Router;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{get, patch};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, AuthedLimited, Json, Query, READ, enforce};
use super::messages::parse_uuid;
use crate::ids::{ChannelId, UserId};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::Report;

const BODY_LIMIT: usize = 4 * 1024;

/// Default and maximum reports returned in one page, matching the plain
/// message list's shape. A page is bounded because the handler pays several
/// indexed queries per report to re-check visibility, and nothing else bounds
/// how many reports members file.
const DEFAULT_LIMIT: i64 = 50;
const MAX_LIMIT: i64 = 200;

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
    /// Who wrote the reported message. Null for a report about a user, for a
    /// message since hard-deleted, and once the author is anonymized.
    subject_author_id: Option<String>,
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
            subject_author_id: report.subject_author_id.map(|id| id.to_string()),
            created_at: report.created_at,
        }
    }
}

/// One page of the queue. The cursor is the `created_at` and `id` of the last
/// report the caller already holds, exclusive and composite: `created_at` is
/// milliseconds, so two reports can share one, and a cursor on the timestamp
/// alone would skip every remaining member of a tied group that a page boundary
/// fell inside. Both or neither - an `after` without an `after_id` is refused
/// rather than silently read as the ambiguous form.
#[derive(Deserialize)]
struct ListParams {
    after: Option<i64>,
    after_id: Option<String>,
    limit: Option<i64>,
}

#[derive(Deserialize)]
struct ResolveReportRequest {
    /// "resolved" or "dismissed".
    resolution: String,
}

/// Lists one page of the open moderation queue, oldest first.
///
/// A report carries the reported content verbatim, so the queue is filtered
/// per channel rather than shown wholesale. `base_permissions` ignores channel
/// overwrites by construction, so a moderator explicitly denied
/// MANAGE_MESSAGES in one channel would otherwise still read every message
/// reported there. Reports with no channel are deployment-wide (a report about
/// a user rather than a message) and stay on the base check alone.
///
/// That exclusion is resolved once, into the set of channels the caller cannot
/// moderate, and applied in the `WHERE` rather than to the page after it is
/// read. Both orders answer the same, but filtering after a `LIMIT` makes a
/// short page ambiguous - a caller cannot tell it from the end of the queue -
/// so a moderator denied MANAGE_MESSAGES in one busy channel would silently
/// stop paging with reports they may read still ahead of them. It also drops
/// what the audit filed this route for: the per-report evaluation, several
/// indexed queries each, is now four queries for the whole page.
async fn list(
    AuthedLimited(ctx): AuthedLimited<READ>,
    Query(params): Query<ListParams>,
    State(state): State<AppState>,
) -> Result<Json<Vec<ReportDto>>, ApiError> {
    require_manage_messages(&state, ctx.user_id).await?;
    let after = match (params.after, params.after_id.as_deref()) {
        (Some(created_at), Some(id)) => Some((created_at, parse_uuid(id)?)),
        (None, None) => None,
        _ => {
            return Err(ApiError::BadRequest(
                "after and after_id go together or not at all",
            ));
        }
    };
    let limit = params.limit.unwrap_or(DEFAULT_LIMIT).clamp(1, MAX_LIMIT);

    let hidden = hidden_channels(&state, ctx.user_id).await?;
    let reports = state.store.list_open_reports(after, &hidden, limit).await?;
    Ok(Json(reports.into_iter().map(ReportDto::from).collect()))
}

/// The channels this caller may not read reports from: every live non-DM
/// channel [`crate::store::Store::list_channels`] returns that they cannot
/// moderate, plus every thread reported against that resolves to one of
/// those.
///
/// The complement rather than the allowed set, because the three kinds of report
/// that are *not* about a live non-DM channel - one with no channel, one about a
/// DM, one about a since-deleted channel - must stay visible on the caller's
/// deployment-wide bit alone, and none of them appears in `list_channels`. An
/// allowed-set predicate would hide all three.
///
/// A thread is the fourth kind absent from `list_channels`, but unlike the
/// other three it is not exempt - it resolves to a real, moderatable parent
/// channel (see [`crate::store::Store::channel_scopes_moderation`]), so a
/// report about one has to be excluded exactly when that parent is. The batch
/// above cannot see that resolution, since it never asks about a thread at
/// all; this loop asks only about the channels open reports actually name and
/// `list_channels` did not already answer for, reusing [`report_visible_in`]
/// rather than a second copy of its resolve-then-check logic.
async fn hidden_channels(state: &AppState, user_id: UserId) -> Result<Vec<ChannelId>, ApiError> {
    let all_ids: std::collections::HashSet<ChannelId> = state
        .store
        .list_channels()
        .await?
        .into_iter()
        .map(|channel| channel.id)
        .collect();
    let moderatable: std::collections::HashSet<ChannelId> = state
        .store
        .channels_where(user_id, Permissions::MANAGE_MESSAGES)
        .await?
        .into_iter()
        .map(|channel| channel.id)
        .collect();

    let mut hidden: Vec<ChannelId> = all_ids
        .iter()
        .copied()
        .filter(|id| !moderatable.contains(id))
        .collect();
    for channel_id in state.store.open_report_channel_ids().await? {
        if !all_ids.contains(&channel_id) && !report_visible_in(state, user_id, channel_id).await {
            hidden.push(channel_id);
        }
    }
    Ok(hidden)
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
        && !report_visible_in(&state, ctx.user_id, channel_id).await
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

/// Whether a base-level moderator may see or act on a report in this channel.
///
/// The caller has already passed the deployment-wide `MANAGE_MESSAGES` check.
/// A report in a live text or voice channel is further restricted to that
/// channel's own moderators, so a moderator excluded from one channel cannot
/// reach into it. A report in a DM or a since-deleted channel has no such
/// moderators to defer to, so it stays with the deployment moderators rather
/// than falling into a per-channel check that grants it to nobody. That hole
/// was accepting DM harassment reports and hiding them forever.
async fn report_visible_in(state: &AppState, user_id: UserId, channel_id: ChannelId) -> bool {
    match state.store.channel_scopes_moderation(channel_id).await {
        Ok(false) => true,
        Ok(true) => state
            .store
            .has_permission(user_id, channel_id, Permissions::MANAGE_MESSAGES)
            .await
            .unwrap_or(false),
        Err(_) => false,
    }
}
