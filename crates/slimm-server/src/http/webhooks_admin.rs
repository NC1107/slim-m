// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Minting, listing, renaming and revoking webhooks. See
//! `docs/decisions/0030-incoming-webhooks.md`, and its "admin surface"
//! addendum for what this file's routes had to decide beyond delivery.
//!
//! Gated on `MANAGE_SERVER` exactly like `bots.rs`, and deliberately not
//! reusing any of its handlers: a webhook has no permissions to grant and no
//! session to revoke, so the shapes that make up most of that file (the
//! managed role, `require_human`, escalation guards) do not apply here.
//!
//! The token is returned exactly once, by [`create`], and unrecoverable
//! afterwards - the same shape `bots.rs::create` uses.

use axum::Router;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{get, patch, post};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::auth::validate_label;
use super::error::ApiError;
use super::extract::{Authed, Json, enforce, require_manage_server};
use super::messages::parse_uuid;
use crate::ids::{ChannelId, WebhookId};
use crate::ratelimit::Class;
use crate::store::Webhook;

/// A create or rename body is a channel id and a short label; nowhere near
/// the delivery route's own, much larger, body limit.
const BODY_LIMIT: usize = 1024;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/webhooks", get(list).post(create))
        .route("/webhooks/{webhook_id}", patch(rename))
        .route("/webhooks/{webhook_id}/revoke", post(revoke))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

#[derive(Deserialize)]
struct CreateWebhookDto {
    channel_id: String,
    label: String,
}

#[derive(Deserialize)]
struct RenameWebhookDto {
    label: String,
}

/// A webhook, as the admin surface lists it. Never carries a token.
#[derive(Serialize)]
struct WebhookDto {
    id: String,
    channel_id: String,
    label: String,
    created_at: i64,
    last_delivery_at: Option<i64>,
    /// Absent if the admin who minted this has since deleted their own
    /// account; the webhook itself keeps working either way.
    created_by_display_name: Option<String>,
}

impl From<Webhook> for WebhookDto {
    fn from(webhook: Webhook) -> Self {
        Self {
            id: webhook.id.to_string(),
            channel_id: webhook.channel_id.to_string(),
            label: webhook.label,
            created_at: webhook.created_at,
            last_delivery_at: webhook.last_delivery_at,
            created_by_display_name: webhook.created_by_display_name,
        }
    }
}

/// A created webhook, with its delivery path. The only response that ever
/// carries it.
///
/// A path (`/webhooks/{id}/{token}`), not a full URL: the server has no
/// notion of its own externally reachable origin (it may sit behind a
/// reverse proxy at any hostname), while the client already knows the
/// address it is talking to this deployment on. The client joins the two to
/// show a pasteable URL.
#[derive(Serialize)]
struct NewWebhookDto {
    webhook: WebhookDto,
    delivery_path: String,
}

async fn list(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
) -> Result<Json<Vec<WebhookDto>>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::AuthedRead)?;
    require_manage_server(&state, ctx.user_id).await?;
    let webhooks = state.store.list_webhooks().await?;
    Ok(Json(webhooks.into_iter().map(WebhookDto::from).collect()))
}

/// Labels follow the same rule a display name does: `validate_label`, not a
/// bespoke check, so a webhook's name is held to the same bar a person's is.
async fn create(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
    Json(body): Json<CreateWebhookDto>,
) -> Result<(StatusCode, Json<NewWebhookDto>), ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_server(&state, ctx.user_id).await?;

    let label = body.label.trim();
    validate_label(label, "label must be 1 to 64 characters")?;
    let channel_id = ChannelId(parse_uuid(&body.channel_id)?);
    if state.store.channel(channel_id).await?.is_none() {
        return Err(ApiError::NotFound("no such channel"));
    }

    let minted = state
        .store
        .create_webhook(channel_id, label, ctx.user_id)
        .await?;
    let delivery_path = format!("/webhooks/{}/{}", minted.webhook.id, minted.token);
    Ok((
        StatusCode::CREATED,
        Json(NewWebhookDto {
            webhook: minted.webhook.into(),
            delivery_path,
        }),
    ))
}

/// Renames a webhook's admin-facing label. Returns 404 rather than a
/// permission-shaped refusal for an id that never existed, the same uniform
/// answer delivery gives an unknown id.
async fn rename(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
    Path(webhook_id): Path<String>,
    Json(body): Json<RenameWebhookDto>,
) -> Result<Json<WebhookDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_server(&state, ctx.user_id).await?;
    let webhook_id = WebhookId(parse_uuid(&webhook_id)?);

    let label = body.label.trim();
    validate_label(label, "label must be 1 to 64 characters")?;

    match state.store.rename_webhook(webhook_id, label).await? {
        Some(webhook) => Ok(Json(webhook.into())),
        None => Err(ApiError::NotFound("no such webhook")),
    }
}

/// Revokes a webhook. Its URL 404s on its very next delivery attempt - see
/// `Store::revoke_webhook`'s own doc for why there is nothing else to close.
async fn revoke(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
    Path(webhook_id): Path<String>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_server(&state, ctx.user_id).await?;
    let webhook_id = WebhookId(parse_uuid(&webhook_id)?);
    if !state.store.revoke_webhook(webhook_id, ctx.user_id).await? {
        return Err(ApiError::NotFound("no such webhook"));
    }
    Ok(StatusCode::NO_CONTENT)
}
