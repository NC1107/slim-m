// SPDX-License-Identifier: AGPL-3.0-only
//! Attachment routes: upload bytes once, reference them by content hash when
//! sending a message ([`super::messages`]), fetch them back here.
//!
//! Upload accepts only a fixed content-type allowlist ([`media`]), decided by
//! sniffing the bytes themselves - never a client-declared Content-Type
//! header and never a filename extension, both of which a client fully
//! controls. That is the actual security boundary: this deployment has no
//! content or media scanning by owner decision, so what gets accepted and how
//! it is served back is the whole defense against a stored-XSS upload.
//!
//! Fetch is the other half of that boundary. It is gated on the same
//! VIEW_CHANNEL permission a caller needs to read the message an attachment
//! belongs to - an unguessable hex id is not access control on its own, and
//! this never treats it as such.

use axum::body::{Body, Bytes};
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::request::Parts;
use axum::http::{HeaderName, HeaderValue, StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, enforce};
use crate::media;
use crate::permissions::Permissions;
use crate::ratelimit::Class;

/// A fetched attachment's bytes never change (they are keyed by their own
/// content hash), so a client may cache one forever.
const IMMUTABLE_CACHE: &str = "private, max-age=31536000, immutable";

/// The attachment routes, mounted by [`super::router`] right after
/// `users::routes()`. `max_attachment_bytes` comes from `state.media`
/// at router-build time (see `http::router`), so the axum-level body-size
/// safety net always matches the operator-configured ceiling rather than a
/// separate hardcoded constant that could quietly diverge from it.
pub fn routes(max_attachment_bytes: u64) -> Router<AppState> {
    Router::new()
        .route("/attachments", post(upload))
        .route("/attachments/{attachment_id}", get(fetch))
        .layer(DefaultBodyLimit::max(max_attachment_bytes as usize))
}

// --- Wire types ---

#[derive(Serialize)]
struct AttachmentUploadDto {
    id: String,
    filename: String,
    content_type: String,
    size: i64,
}

#[derive(Deserialize)]
struct UploadParams {
    filename: Option<String>,
}

// --- Handlers ---

/// Stores uploaded bytes under their own sha256 and returns the hex id a
/// message can then reference.
///
/// The file is written before the metadata row on purpose: a crash between
/// the two leaves an orphaned file (harmless, eventually swept) rather than a
/// row that promises bytes which were never actually written.
async fn upload(
    Authed(ctx): Authed,
    parts: Parts,
    Query(params): Query<UploadParams>,
    State(state): State<AppState>,
    body: Bytes,
) -> Result<(StatusCode, Json<AttachmentUploadDto>), ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Upload)?;

    if body.is_empty() {
        return Err(ApiError::BadRequest("attachment is empty"));
    }
    if body.len() as u64 > state.media.max_attachment_bytes() {
        return Err(ApiError::BadRequest("attachment is too large"));
    }
    // Decided from the bytes only - see the module doc for why this is the
    // whole security boundary here.
    let content_type = media::sniff_content_type(&body)
        .ok_or(ApiError::BadRequest("unsupported attachment type"))?;
    let filename = media::sanitize_filename(params.filename.as_deref().unwrap_or("file"));

    let sha256 = Sha256::digest(&body).to_vec();
    let hex_id = media::to_hex(&sha256);
    let size = body.len() as i64;

    // Bytes before the metadata row, never the other way round; see the
    // ordering note on this function.
    state
        .media
        .write_attachment(&hex_id, body.to_vec())
        .await
        .map_err(|err| {
            tracing::error!(error = %err, "failed to write an uploaded attachment");
            ApiError::Internal
        })?;
    state
        .store
        .store_attachment(&sha256, size, content_type, &filename)
        .await?;

    Ok((
        StatusCode::CREATED,
        Json(AttachmentUploadDto {
            id: hex_id,
            filename,
            content_type: content_type.to_owned(),
            size,
        }),
    ))
}

/// Serves stored bytes back, gated on the same VIEW_CHANNEL a caller needs to
/// read the message the attachment belongs to.
///
/// The check runs across every channel that has attached these bytes, because
/// content addressing means more than one message, in more than one channel,
/// can share them. An id nothing has ever attached - still mid-compose, or
/// already swept as an orphan - reports the same 404 as one that never
/// existed, for anyone including whoever uploaded it: existence follows
/// permission here exactly as it does for a channel or a message elsewhere in
/// this API.
async fn fetch(
    Authed(ctx): Authed,
    Path(attachment_id): Path<String>,
    State(state): State<AppState>,
) -> Result<Response, ApiError> {
    let sha256 = media::from_hex(&attachment_id)
        .filter(|bytes| bytes.len() == 32)
        .ok_or(ApiError::BadRequest("invalid attachment id"))?;

    // Unreferenced bytes 404 rather than 403, for everyone; see the access
    // control note on this function.
    let channels = state.store.channels_referencing_attachment(&sha256).await?;
    if channels.is_empty() {
        return Err(ApiError::NotFound("attachment not found"));
    }
    let mut allowed = false;
    for channel_id in channels {
        if state
            .store
            .has_permission(ctx.user_id, channel_id, Permissions::VIEW_CHANNEL)
            .await?
        {
            allowed = true;
            break;
        }
    }
    if !allowed {
        return Err(ApiError::Forbidden);
    }

    let meta = state
        .store
        .attachment_summary(&sha256)
        .await?
        .ok_or(ApiError::NotFound("attachment not found"))?;
    let bytes = state
        .media
        .read_attachment(&attachment_id)
        .await
        .map_err(|err| {
            tracing::error!(error = %err, "failed to read a stored attachment");
            ApiError::Internal
        })?;

    Ok(serve(bytes, &meta.content_type, &meta.filename))
}

/// Builds the byte response, shared with the avatar fetch in
/// `super::users` so both carry identical security headers.
///
/// `content_type` is never trusted from the caller: both call sites pass a
/// value this module itself already sniffed from stored bytes, so this only
/// ever serves one of the allowlisted types.
///
/// The filename is sanitized again here even though the stored value was
/// already sanitized at upload time. It is cheap, since the function is
/// idempotent, and it means this response never depends on every future write
/// path having remembered to.
pub(crate) fn serve(bytes: Vec<u8>, content_type: &str, filename: &str) -> Response {
    let disposition_kind = if media::is_inline(content_type) {
        "inline"
    } else {
        "attachment"
    };
    // Re-sanitized rather than trusted from storage; see the note above.
    let safe_name = media::sanitize_filename(filename);
    let disposition = format!("{disposition_kind}; filename=\"{safe_name}\"");

    let mut response = Body::from(bytes).into_response();
    let headers = response.headers_mut();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_str(content_type)
            .unwrap_or_else(|_| HeaderValue::from_static("application/octet-stream")),
    );
    // `sanitize_filename` guarantees printable ASCII so this cannot fail; the
    // fallback keeps a future change to that guarantee a response, not a panic.
    let disposition_value = HeaderValue::from_str(&disposition)
        .unwrap_or_else(|_| HeaderValue::from_static("attachment"));
    headers.insert(header::CONTENT_DISPOSITION, disposition_value);
    // Not a named constant in the `http` crate (it is a non-standard header),
    // unlike Content-Type and Content-Disposition above.
    headers.insert(
        HeaderName::from_static("x-content-type-options"),
        HeaderValue::from_static("nosniff"),
    );
    headers.insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static(IMMUTABLE_CACHE),
    );
    response
}
