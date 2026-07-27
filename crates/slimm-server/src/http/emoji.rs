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

use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::response::Response;
use axum::routing::{delete, get};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::AppState;
use super::attachments::serve;
use super::error::ApiError;
use super::extract::Authed;
use super::extract::enforce;
use crate::ids::EmojiId;
use crate::media;
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::CreateEmojiError;

/// An emoji's bytes are content-addressed, so they never change under an id.
const IMMUTABLE_CACHE: &str = "private, max-age=31536000, immutable";

/// Longest `:shortcode:` accepted. Long enough for a readable name, short
/// enough that the list stays a list rather than a wall.
const MAX_NAME_LEN: usize = 32;

/// Emoji are drawn inline at text size, so the ceiling is far below an
/// attachment's: a megabyte is already generous for something rendered at
/// about 20 points.
const MAX_EMOJI_BYTES: u64 = 1024 * 1024;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/emoji", get(list).post(upload))
        .route("/emoji/{emoji_id}", delete(remove))
        .route("/emoji/{emoji_id}/image", get(image))
        .layer(DefaultBodyLimit::max(MAX_EMOJI_BYTES as usize))
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
    Authed(_ctx): Authed,
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
    axum::extract::Query(params): axum::extract::Query<UploadParams>,
    State(state): State<AppState>,
    body: Bytes,
) -> Result<(StatusCode, Json<CustomEmojiDto>), ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Upload)?;
    require_manage_server(&state, &ctx).await?;

    let name = normalize_name(&params.name).ok_or(ApiError::BadRequest(
        "emoji name must be 1 to 32 characters of a-z, 0-9 or _",
    ))?;

    if body.is_empty() {
        return Err(ApiError::BadRequest("emoji is empty"));
    }
    if body.len() as u64 > MAX_EMOJI_BYTES {
        return Err(ApiError::BadRequest("emoji is too large"));
    }
    // Sniffed from the bytes, never taken from the request; the inline
    // (image) subset only, since an emoji is drawn rather than downloaded.
    let content_type = media::sniff_content_type(&body)
        .filter(|ct| media::is_inline(ct))
        .ok_or(ApiError::BadRequest("unsupported emoji type"))?;

    let sha256 = Sha256::digest(&body).to_vec();
    let hex_id = media::to_hex(&sha256);
    let size = body.len() as i64;

    // Bytes before the metadata row, the same ordering attachments uses: a
    // row pointing at bytes that are not there yet is the worse failure.
    state
        .media
        .write_attachment(&hex_id, body.to_vec())
        .await
        .map_err(|err| {
            tracing::error!(error = %err, "failed to write an uploaded emoji");
            ApiError::Internal
        })?;
    state
        .store
        .store_attachment(&sha256, size, content_type, &format!("{name}.img"))
        .await?;

    let created = state
        .store
        .create_custom_emoji(EmojiId::generate(), &name, &sha256, ctx.user_id)
        .await?;

    match created {
        Ok(emoji) => Ok((
            StatusCode::CREATED,
            Json(CustomEmojiDto {
                id: emoji.id,
                name: emoji.name,
                uploader_id: emoji.uploader_id,
                created_at: emoji.created_at,
            }),
        )),
        Err(CreateEmojiError::NameTaken) => {
            Err(ApiError::Conflict("an emoji with that name already exists"))
        }
        Err(CreateEmojiError::Full) => {
            Err(ApiError::Conflict("this deployment is at its emoji limit"))
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
    Authed(_ctx): Authed,
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

/// Lowercases and accepts only what a member can type unambiguously between
/// colons. Returns None if nothing usable is left.
fn normalize_name(raw: &str) -> Option<String> {
    let name: String = raw
        .trim()
        .to_ascii_lowercase()
        .chars()
        .map(|c| if c == ' ' || c == '-' { '_' } else { c })
        .filter(|c| c.is_ascii_alphanumeric() || *c == '_')
        .collect();
    if name.is_empty() || name.len() > MAX_NAME_LEN {
        return None;
    }
    Some(name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_name_is_reduced_to_what_can_be_typed_between_colons() {
        assert_eq!(normalize_name("Big Smile").as_deref(), Some("big_smile"));
        assert_eq!(
            normalize_name("party-parrot").as_deref(),
            Some("party_parrot")
        );
        assert_eq!(normalize_name("  OK  ").as_deref(), Some("ok"));
        assert_eq!(normalize_name(":::").as_deref(), None);
        assert_eq!(normalize_name("").as_deref(), None);
        assert_eq!(normalize_name(&"x".repeat(33)).as_deref(), None);
    }

    /// Two spellings of one name must not become two emoji, or a message
    /// saying `:big_smile:` has no single answer.
    #[test]
    fn spellings_that_normalize_together_collide_rather_than_coexisting() {
        assert_eq!(normalize_name("Big Smile"), normalize_name("big-smile"));
    }
}
