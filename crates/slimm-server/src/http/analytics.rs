// SPDX-License-Identifier: AGPL-3.0-only
//! Space usage analytics: one resource, gated on MANAGE_SERVER same as
//! `/space/settings`, that reads as disabled rather than refusing outright
//! when the toggle is off. See `docs/decisions/0008-space-analytics.md`.

use axum::Router;
use axum::extract::{DefaultBodyLimit, State};
use axum::http::request::Parts;
use axum::routing::get;
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, Json, enforce};
use crate::permissions::Permissions;
use crate::process_metrics::current_rss_bytes;
use crate::ratelimit::Class;
use crate::store::AnalyticsStats;

const BODY_LIMIT: usize = 256;

/// The Space analytics routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/space/analytics", get(read).patch(update))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

#[derive(Serialize)]
struct DayCountDto {
    date: String,
    count: i64,
}

#[derive(Serialize)]
struct MetricSampleDto {
    sampled_at: i64,
    rss_bytes: i64,
}

#[derive(Serialize)]
struct AnalyticsStatsDto {
    total_messages: i64,
    member_count: i64,
    channel_count: i64,
    attachment_bytes: i64,
    messages_by_day: Vec<DayCountDto>,
    active_hours: [i64; 24],
    memory_samples: Vec<MetricSampleDto>,
}

impl From<AnalyticsStats> for AnalyticsStatsDto {
    fn from(stats: AnalyticsStats) -> Self {
        Self {
            total_messages: stats.total_messages,
            member_count: stats.member_count,
            channel_count: stats.channel_count,
            attachment_bytes: stats.attachment_bytes,
            messages_by_day: stats
                .messages_by_day
                .into_iter()
                .map(|d| DayCountDto {
                    date: d.date,
                    count: d.count,
                })
                .collect(),
            active_hours: stats.active_hours,
            memory_samples: stats
                .memory_samples
                .into_iter()
                .map(|s| MetricSampleDto {
                    sampled_at: s.sampled_at,
                    rss_bytes: s.rss_bytes,
                })
                .collect(),
        }
    }
}

/// `stats` is present only when `enabled` is true: a disabled deployment
/// answers 200 with nothing computed, rather than a 403 or 404 a client would
/// have to special-case apart from a real permission or routing failure.
#[derive(Serialize)]
struct AnalyticsDto {
    enabled: bool,
    stats: Option<AnalyticsStatsDto>,
}

#[derive(Deserialize)]
struct UpdateAnalyticsDto {
    enabled: bool,
}

async fn read(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
) -> Result<Json<AnalyticsDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Read)?;
    require_manage_server(&state, &ctx).await?;
    Ok(Json(current_analytics(&state).await?))
}

async fn update(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
    Json(body): Json<UpdateAnalyticsDto>,
) -> Result<Json<AnalyticsDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_server(&state, &ctx).await?;
    state.store.set_analytics_enabled(body.enabled).await?;
    Ok(Json(current_analytics(&state).await?))
}

/// Samples this process's own memory on the way past, only when the toggle
/// is on: an admin with analytics off must add nothing to what runs.
async fn current_analytics(state: &AppState) -> Result<AnalyticsDto, ApiError> {
    let enabled = state.store.analytics_enabled().await?;
    if !enabled {
        return Ok(AnalyticsDto {
            enabled: false,
            stats: None,
        });
    }
    if let Some(rss) = current_rss_bytes() {
        state.store.maybe_record_metrics_sample(rss).await?;
    }
    let stats = state.store.analytics_stats().await?;
    Ok(AnalyticsDto {
        enabled: true,
        stats: Some(stats.into()),
    })
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
