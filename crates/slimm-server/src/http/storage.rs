// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Operator-visible storage usage and sweep health: one read-only resource,
//! gated on MANAGE_SERVER the same as `/space/analytics`, so a self-hosted
//! operator can see disk pressure and whether the background sweeps are
//! actually running before a write ever fails. See
//! `crates/slimm-server/src/store/storage.rs` for how each figure is
//! computed.
//!
//! **Rate limit**: `Class::Write`, not `Class::AuthedRead`, for the same
//! reason `/space/analytics` charges it - `attachment_bytes_by_channel` is a
//! real cross-table aggregation, not a single-row lookup.

use axum::Router;
use axum::extract::State;
use axum::http::request::Parts;
use axum::routing::get;
use serde::Serialize;

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, Json, enforce};
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::{ChannelStorage, DatabaseBytes, MAX_STORAGE_CHANNEL_ROWS, SweepStatus};

/// The Space storage route, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new().route("/space/storage", get(read))
}

#[derive(Serialize)]
struct ChannelStorageDto {
    channel_id: String,
    name: String,
    attachment_bytes: i64,
}

impl From<ChannelStorage> for ChannelStorageDto {
    fn from(channel: ChannelStorage) -> Self {
        Self {
            channel_id: channel.channel_id.to_string(),
            name: channel.name,
            attachment_bytes: channel.attachment_bytes,
        }
    }
}

#[derive(Serialize)]
struct SweepStatusDto {
    name: String,
    last_run_at: i64,
    last_reclaimed: i64,
}

impl From<SweepStatus> for SweepStatusDto {
    fn from(sweep: SweepStatus) -> Self {
        Self {
            name: sweep.name,
            last_run_at: sweep.last_run_at,
            last_reclaimed: sweep.last_reclaimed,
        }
    }
}

#[derive(Serialize)]
struct StorageDto {
    database_bytes: i64,
    database_reclaimable_bytes: i64,
    attachment_bytes: i64,
    top_channels: Vec<ChannelStorageDto>,
    sweeps: Vec<SweepStatusDto>,
}

async fn read(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
) -> Result<Json<StorageDto>, ApiError> {
    // Write, not AuthedRead: attachment_bytes_by_channel does real cross-table aggregation.
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_server(&state, &ctx).await?;

    let DatabaseBytes {
        database_bytes,
        database_reclaimable_bytes,
    } = state.store.database_bytes().await?;
    let attachment_bytes = state.store.attachment_bytes_total().await?;
    let top_channels = state
        .store
        .attachment_bytes_by_channel(MAX_STORAGE_CHANNEL_ROWS)
        .await?;
    let sweeps = state.store.sweep_statuses().await?;

    Ok(Json(StorageDto {
        database_bytes,
        database_reclaimable_bytes,
        attachment_bytes,
        top_channels: top_channels.into_iter().map(Into::into).collect(),
        sweeps: sweeps.into_iter().map(Into::into).collect(),
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
