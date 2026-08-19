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

use std::io::SeekFrom;

use axum::Router;
use axum::body::Body;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::{HeaderMap, HeaderName, HeaderValue, StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use tokio::io::{AsyncReadExt, AsyncSeekExt};
use tokio_util::io::ReaderStream;

use super::AppState;
use super::error::ApiError;
use super::extract::{ASSET, AuthedLimited, Bytes, Json, Query, UPLOAD};
use super::message_dto::AttachmentDto;
use crate::media;
use crate::permissions::Permissions;
use crate::store::AttachmentSummary;

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
///
/// The rate limit is charged in the signature rather than in the body, and that
/// ordering is the point: `Bytes` is a `FromRequest` extractor, so it resolves
/// last and the whole body was buffered before the old `enforce` call ever ran.
/// A caller over budget, or holding no ATTACH_FILES bit at all, still cost the
/// process the memory and the bandwidth of the upload.
///
/// Requires ATTACH_FILES deployment-wide. An upload names no channel, so the
/// per-channel check still happens when the resulting id is attached to a
/// message; this is the half that was missing entirely. Until it existed the
/// handler asked for no permission of any kind, so a member denied
/// attachments everywhere - or one currently timed out - could still write
/// bytes into media storage.
async fn upload(
    AuthedLimited(ctx): AuthedLimited<UPLOAD>,
    Query(params): Query<UploadParams>,
    State(state): State<AppState>,
    Bytes(body): Bytes,
) -> Result<(StatusCode, Json<AttachmentDto>), ApiError> {
    // Deployment-wide because an upload names no channel; see the note above.
    if !state
        .store
        .base_permissions(ctx.user_id)
        .await?
        .contains(Permissions::ATTACH_FILES)
    {
        return Err(ApiError::Forbidden);
    }

    if body.is_empty() {
        return Err(ApiError::BadRequest("attachment is empty"));
    }
    if body.len() as u64 > state.media.max_attachment_bytes() {
        return Err(ApiError::BadRequest("attachment is too large"));
    }
    room_for(&state, body.len() as i64).await?;
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
        .store_attachment(&sha256, size, content_type, &filename, Some(ctx.user_id))
        .await?;

    Ok((
        StatusCode::CREATED,
        Json(AttachmentDto::from(AttachmentSummary {
            id: hex_id,
            filename,
            content_type: content_type.to_owned(),
            size,
        })),
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
    AuthedLimited(ctx): AuthedLimited<ASSET>,
    Path(attachment_id): Path<String>,
    headers: HeaderMap,
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
        // 404, not 403, and the difference is the whole point. An attachment id
        // is the content's sha256, so anyone holding a candidate file can
        // compute it; a 403-versus-404 split would tell them whether those
        // exact bytes were shared in a DM or a private channel they cannot see.
        // Existence follows permission here, the same collapse search and the
        // channel API already make.
        return Err(ApiError::NotFound("attachment not found"));
    }

    let meta = state
        .store
        .attachment_summary(&sha256)
        .await?
        .ok_or(ApiError::NotFound("attachment not found"))?;
    let (file, total_len) = state
        .media
        .open_attachment(&attachment_id)
        .await
        .map_err(|err| {
            tracing::error!(error = %err, "failed to open a stored attachment");
            ApiError::Internal
        })?;

    let range_header = headers.get(header::RANGE).and_then(|v| v.to_str().ok());
    serve_ranged(
        file,
        total_len,
        range_header,
        &meta.content_type,
        &meta.filename,
    )
    .await
}

/// The byte range a `Range` header resolves to against a known total length.
enum ByteRange {
    /// No usable range: serve the whole body as `200`. Covers an absent header
    /// and, per RFC 9110, a header this server chooses not to honour (a
    /// multi-range request, or a syntactically invalid one), which a client
    /// must accept as a full response.
    Full,
    /// A single satisfiable range, both bounds inclusive: serve `206`.
    Partial { start: u64, end: u64 },
    /// A syntactically valid range that no part of the body can satisfy: serve
    /// `416` so the client learns the length rather than retrying blindly.
    Unsatisfiable,
}

/// Resolves a `Range` request-header value against `total`, following RFC 9110:
/// only `bytes` units, a single range, and anything malformed or multi-range
/// falls back to a full response rather than an error.
fn parse_range(header: Option<&str>, total: u64) -> ByteRange {
    let Some(spec) = header.and_then(|h| h.trim().strip_prefix("bytes=")) else {
        return ByteRange::Full;
    };
    // A comma means multiple ranges; serve the whole body, not a multipart/byteranges response.
    if spec.contains(',') {
        return ByteRange::Full;
    }
    let Some((raw_start, raw_end)) = spec.split_once('-') else {
        return ByteRange::Full;
    };
    let (start, end) = match (raw_start.trim(), raw_end.trim()) {
        ("", "") => return ByteRange::Full,
        // `-N`: the final N bytes. N == 0 requests nothing satisfiable.
        ("", suffix) => {
            let Ok(len) = suffix.parse::<u64>() else {
                return ByteRange::Full;
            };
            if len == 0 || total == 0 {
                return ByteRange::Unsatisfiable;
            }
            (total.saturating_sub(len), total - 1)
        }
        // `start-`: from start to the end of the body.
        (start, "") => {
            let Ok(start) = start.parse::<u64>() else {
                return ByteRange::Full;
            };
            (start, total.saturating_sub(1))
        }
        // `start-end`, end clamped into the body.
        (start, end) => {
            let (Ok(start), Ok(end)) = (start.parse::<u64>(), end.parse::<u64>()) else {
                return ByteRange::Full;
            };
            (start, end.min(total.saturating_sub(1)))
        }
    };
    if total == 0 || start >= total || start > end {
        return ByteRange::Unsatisfiable;
    }
    ByteRange::Partial { start, end }
}

/// Streams an open attachment file as the response, honouring a single
/// `Range`. Always advertises `Accept-Ranges: bytes` and sets an explicit
/// `Content-Length`, neither of which a streamed body carries on its own.
async fn serve_ranged(
    mut file: tokio::fs::File,
    total_len: u64,
    range_header: Option<&str>,
    content_type: &str,
    filename: &str,
) -> Result<Response, ApiError> {
    let response = match parse_range(range_header, total_len) {
        ByteRange::Unsatisfiable => {
            let mut response = StatusCode::RANGE_NOT_SATISFIABLE.into_response();
            response.headers_mut().insert(
                header::CONTENT_RANGE,
                HeaderValue::from_str(&format!("bytes */{total_len}"))
                    .unwrap_or_else(|_| HeaderValue::from_static("bytes */0")),
            );
            response
        }
        ByteRange::Full => {
            let body = Body::from_stream(ReaderStream::new(file));
            let mut response = body.into_response();
            set_content_length(response.headers_mut(), total_len);
            response
        }
        ByteRange::Partial { start, end } => {
            file.seek(SeekFrom::Start(start)).await.map_err(|err| {
                tracing::error!(error = %err, "failed to seek within a stored attachment");
                ApiError::Internal
            })?;
            let span = end - start + 1;
            let body = Body::from_stream(ReaderStream::new(file.take(span)));
            let mut response = body.into_response();
            *response.status_mut() = StatusCode::PARTIAL_CONTENT;
            let headers = response.headers_mut();
            set_content_length(headers, span);
            headers.insert(
                header::CONTENT_RANGE,
                HeaderValue::from_str(&format!("bytes {start}-{end}/{total_len}"))
                    .unwrap_or_else(|_| HeaderValue::from_static("bytes */0")),
            );
            response
        }
    };
    let mut response = response;
    let headers = response.headers_mut();
    headers.insert(header::ACCEPT_RANGES, HeaderValue::from_static("bytes"));
    apply_asset_headers(headers, content_type, filename);
    Ok(response)
}

fn set_content_length(headers: &mut HeaderMap, len: u64) {
    if let Ok(value) = HeaderValue::from_str(&len.to_string()) {
        headers.insert(header::CONTENT_LENGTH, value);
    }
}

/// Serves already-buffered bytes, for the small assets that are read whole
/// anyway: avatars (`super::users`) and custom emoji (`super::emoji`). Large
/// attachments stream instead, through [`serve_ranged`]; both share
/// [`apply_asset_headers`], so every asset response carries identical
/// security headers.
pub(crate) fn serve(bytes: Vec<u8>, content_type: &str, filename: &str) -> Response {
    let mut response = Body::from(bytes).into_response();
    apply_asset_headers(response.headers_mut(), content_type, filename);
    response
}

/// Sets the security and caching headers every asset response carries,
/// buffered ([`serve`]) or streamed ([`serve_ranged`]), so both are governed
/// by one definition rather than two that can drift.
///
/// `content_type` is never trusted from the caller; every call site passes a
/// value this module already sniffed from the stored bytes, so this only ever
/// serves an allowlisted type. The filename is re-sanitized here even though
/// the stored value already was: it is cheap and idempotent, and it means the
/// response never depends on every future write path having remembered to.
fn apply_asset_headers(headers: &mut HeaderMap, content_type: &str, filename: &str) {
    let disposition_kind = if media::is_inline(content_type) {
        "inline"
    } else {
        "attachment"
    };
    let safe_name = media::sanitize_filename(filename);
    let disposition = format!("{disposition_kind}; filename=\"{safe_name}\"");

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
}

/// Refuses the upload if storing `incoming` bytes would put the deployment over
/// `SLIMM_MAX_TOTAL_ATTACHMENT_BYTES`.
///
/// Checked before the bytes are written, never after, so a refusal leaves
/// nothing on disk to reclaim - the same ordering the per-upload size limit
/// above it uses.
///
/// Two things it deliberately is not. It is not a reservation: two uploads
/// racing the last few bytes can both pass and land slightly over, which costs
/// at most one attachment's worth and is the right trade against serialising
/// every upload behind a write lock. And it is not a quota per account, which
/// would need a policy answer about who gets how much that nobody has asked
/// for; this is the disk, and the disk is shared.
pub(super) async fn room_for(state: &AppState, incoming: i64) -> Result<(), ApiError> {
    let Some(ceiling) = state.media.max_total_attachment_bytes() else {
        return Ok(());
    };
    let held = state.store.total_attachment_bytes().await?;
    if held.saturating_add(incoming) as u64 > ceiling {
        return Err(ApiError::InsufficientStorage);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// HTML and SVG sniff to the `text/plain` fallback (see
    /// `media::content_type`'s module doc), so this drives the real `serve`
    /// handler with each and asserts the response a browser actually gets:
    /// a forced download, never an inline render, with `nosniff` set too.
    #[test]
    fn html_and_svg_sniffed_as_text_are_served_as_a_forced_download() {
        for bytes in [
            b"<html><body><script>alert(1)</script></body></html>".to_vec(),
            b"<svg xmlns=\"http://www.w3.org/2000/svg\" onload=\"alert(1)\"></svg>".to_vec(),
        ] {
            let content_type = media::sniff_content_type(&bytes);
            assert_eq!(content_type, Some("text/plain"));
            let response = serve(bytes, content_type.unwrap(), "evil.html");

            let disposition = response
                .headers()
                .get(header::CONTENT_DISPOSITION)
                .unwrap()
                .to_str()
                .unwrap();
            assert!(
                disposition.starts_with("attachment"),
                "must never be inline: {disposition}"
            );

            let nosniff = response
                .headers()
                .get(HeaderName::from_static("x-content-type-options"))
                .unwrap();
            assert_eq!(nosniff, "nosniff");
        }
    }
}
