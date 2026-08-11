// SPDX-License-Identifier: AGPL-3.0-only
//! Custom emoji: the deployment's own named images.
//!
//! Access is deliberately not the attachment rule. An attachment is readable
//! by whoever may view a channel referencing it; an emoji is readable by every
//! authenticated member, because it renders inside any message they may
//! already read, and gating it per channel would leak which channels use which
//! emoji. Writing is gated on MANAGE_SERVER, the bit that already means
//! "change what this deployment is".
//!
//! The bytes go through `media` and the `attachments` row exactly as a message
//! attachment does, so the storage, the sniffing and the dedup are one
//! implementation rather than two.
//!
//! Naming and creation live in [`crate::emoji`], shared with the bulk import,
//! so this module only turns one caller's request into that call and its
//! result into a status code.

use axum::Router;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::response::Response;
use axum::routing::{delete, get};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::attachments::serve;
use super::error::ApiError;
use super::extract::Authed;
use super::extract::enforce;
use super::extract::{ASSET, AuthedLimited, Bytes, Json, Query, READ};
use crate::emoji::{self, AddError};
use crate::ids::EmojiId;
use crate::media;
use crate::permissions::Permissions;
use crate::ratelimit::Class;

/// An emoji's bytes are content-addressed, so they never change under an id.
const IMMUTABLE_CACHE: &str = "private, max-age=31536000, immutable";

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/emoji", get(list).post(upload))
        .route("/emoji/{emoji_id}", delete(remove))
        .route("/emoji/{emoji_id}/image", get(image))
        .layer(DefaultBodyLimit::max(emoji::MAX_IMAGE_BYTES as usize))
}

// --- Wire types ---

#[derive(Debug, Serialize)]
pub struct CustomEmojiDto {
    pub id: String,
    pub name: String,
    pub uploader_id: Option<String>,
    pub created_at: i64,
}

#[derive(Debug, Deserialize)]
pub struct UploadParams {
    pub name: String,
}

// --- Handlers ---

/// Every emoji in the deployment, for any authenticated caller.
async fn list(
    AuthedLimited(_ctx): AuthedLimited<READ>,
    State(state): State<AppState>,
) -> Result<Json<Vec<CustomEmojiDto>>, ApiError> {
    let emoji = state.store.list_custom_emoji().await?;
    Ok(Json(
        emoji
            .into_iter()
            .map(|e| CustomEmojiDto {
                id: e.id,
                name: e.name,
                uploader_id: e.uploader_id,
                created_at: e.created_at,
            })
            .collect(),
    ))
}

/// Adds an emoji. The name is normalised to what a member can actually type
/// between colons, so `:Big Smile:` and `:big_smile:` cannot both exist and
/// then disagree about which one a message meant.
async fn upload(
    Authed(ctx): Authed,
    parts: Parts,
    Query(params): Query<UploadParams>,
    State(state): State<AppState>,
    Bytes(body): Bytes,
) -> Result<(StatusCode, Json<CustomEmojiDto>), ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Upload)?;
    require_manage_server(&state, &ctx).await?;

    super::attachments::room_for(&state, body.len() as i64).await?;
    let created = emoji::add_emoji(
        &state.store,
        &state.media,
        &params.name,
        body.to_vec(),
        Some(ctx.user_id),
    )
    .await
    .map_err(refusal)?;

    Ok((
        StatusCode::CREATED,
        Json(CustomEmojiDto {
            id: created.id,
            name: created.name,
            uploader_id: created.uploader_id,
            created_at: created.created_at,
        }),
    ))
}

/// The status code each refusal deserves. Everything up to [`AddError::Full`]
/// is something about this request; storage failure is about this server.
fn refusal(err: AddError) -> ApiError {
    match err {
        AddError::UnusableName => {
            ApiError::BadRequest("emoji name must be 1 to 32 characters of a-z, 0-9 or _")
        }
        AddError::Empty => ApiError::BadRequest("emoji is empty"),
        AddError::TooLarge => ApiError::BadRequest("emoji is too large"),
        AddError::UnsupportedType => ApiError::BadRequest("unsupported emoji type"),
        AddError::NameTaken => ApiError::Conflict("an emoji with that name already exists"),
        AddError::Full => ApiError::Conflict("this deployment is at its emoji limit"),
        AddError::Storage(err) => {
            tracing::error!(error = %err, "failed to store an uploaded emoji");
            ApiError::Internal
        }
    }
}

/// Removes an emoji. Idempotent: deleting one already gone is a 204, so a
/// retry never has to distinguish "gone" from "never existed".
async fn remove(
    Authed(ctx): Authed,
    parts: Parts,
    Path(emoji_id): Path<String>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_server(&state, &ctx).await?;

    let id = parse_id(&emoji_id)?;
    state.store.delete_custom_emoji(id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Serves an emoji's bytes to any authenticated caller.
async fn image(
    AuthedLimited(_ctx): AuthedLimited<ASSET>,
    Path(emoji_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Response, ApiError> {
    let id = parse_id(&emoji_id)?;
    let sha256 = state
        .store
        .custom_emoji_sha256(id)
        .await?
        .ok_or(ApiError::NotFound("emoji not found"))?;

    let hex = media::to_hex(&sha256);
    let meta = state
        .store
        .attachment_summary(&sha256)
        .await?
        .ok_or(ApiError::NotFound("emoji not found"))?;
    let bytes = state.media.read_attachment(&hex).await.map_err(|err| {
        tracing::error!(error = %err, "failed to read a stored emoji");
        ApiError::Internal
    })?;

    let mut response = serve(bytes, &meta.content_type, &meta.filename);
    response.headers_mut().insert(
        axum::http::header::CACHE_CONTROL,
        axum::http::HeaderValue::from_static(IMMUTABLE_CACHE),
    );
    Ok(response)
}

// --- Helpers ---

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

fn parse_id(raw: &str) -> Result<EmojiId, ApiError> {
    raw.parse::<uuid::Uuid>()
        .map(EmojiId)
        .map_err(|_| ApiError::BadRequest("invalid emoji id"))
}
