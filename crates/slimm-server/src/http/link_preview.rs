// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Link unfurling: turning a pasted URL into a title/description/image
//! preview card, fetched server-side so a viewer's IP never reaches the
//! third-party host (the same privacy reasoning `gifs.rs` carries), and
//! behind the SSRF guard in [`ssrf`] because the fetched URL is entirely
//! attacker-controlled. See decision 0019.
//!
//! Opt-in per deployment: an operator turns it on with
//! `SLIMM_LINK_PREVIEWS=true`, off by default, so an outbound-fetch surface
//! is never exposed unless the operator asked for it. `GET /version`'s
//! `link_previews_enabled` is what a client checks before ever asking.

mod cache;
mod extract;
mod fetch;
mod ssrf;

use std::sync::Arc;

use axum::Router;
use axum::extract::{Path, State};
use axum::http::{HeaderValue, header};
use axum::response::Response;
use axum::routing::get;
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{ASSET, AuthedLimited, LINK_PREVIEW, Query};
use crate::config::Config;
use crate::media;

use cache::{Cache, CachedPreview};
use fetch::{FetchError, build_client, fetch_image, fetch_preview};
use ssrf::validate;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/link-preview", get(preview))
        .route("/link-preview/image/{token}", get(image))
}

/// This deployment's optional link unfurling, cheap to clone (an
/// `Option<Arc<_>>`) so it lives directly on [`AppState`] the way
/// [`super::gifs::GifSearch`] does.
#[derive(Clone)]
pub struct LinkPreviews {
    inner: Option<Arc<Enabled>>,
}

struct Enabled {
    client: reqwest::Client,
    cache: Cache,
    /// Only ever true under [`LinkPreviews::for_test`]; lets a test reach the
    /// loopback a fake upstream binds to. False in every production instance.
    allow_private: bool,
}

impl LinkPreviews {
    /// Enabled only when `SLIMM_LINK_PREVIEWS` is set; otherwise every route
    /// here answers "not configured", exactly like GIF search with no
    /// provider set.
    pub fn new(config: &Config) -> Self {
        let inner = config.link_previews.then(|| {
            Arc::new(Enabled {
                client: build_client(false),
                cache: Cache::new(),
                allow_private: false,
            })
        });
        Self { inner }
    }

    /// A disabled instance, for a test that builds an [`AppState`] directly.
    pub fn disabled() -> Self {
        Self { inner: None }
    }

    /// An enabled instance for tests, so the SSRF guard and the not-found
    /// paths can be driven through the real router. No test upstream is
    /// reachable through it: the guard blocks the loopback a test server
    /// binds to, which is exactly the behavior worth exercising.
    pub fn for_test() -> Self {
        Self {
            inner: Some(Arc::new(Enabled {
                client: build_client(true),
                cache: Cache::new(),
                allow_private: true,
            })),
        }
    }

    pub fn is_enabled(&self) -> bool {
        self.inner.is_some()
    }

    fn enabled(&self) -> Result<&Enabled, ApiError> {
        self.inner
            .as_deref()
            .ok_or(ApiError::NotConfigured("link previews are not enabled"))
    }
}

#[derive(Deserialize)]
struct PreviewParams {
    url: String,
}

/// The wire shape of a preview. `image_token` (when present) is redeemed at
/// `GET /link-preview/image/{token}`; the client never sees the upstream
/// image URL.
#[derive(Serialize)]
struct LinkPreviewDto {
    url: String,
    title: Option<String>,
    description: Option<String>,
    site_name: Option<String>,
    image_token: Option<String>,
}

fn to_dto(url: &str, cached: CachedPreview) -> LinkPreviewDto {
    LinkPreviewDto {
        url: url.to_owned(),
        title: cached.title,
        description: cached.description,
        site_name: cached.site_name,
        image_token: cached.image_token,
    }
}

impl From<FetchError> for ApiError {
    fn from(err: FetchError) -> Self {
        match err {
            // A refused (blocked or malformed) URL is the caller's own doing.
            FetchError::Refused => ApiError::BadRequest("that link cannot be previewed"),
            // A public URL that simply did not yield a preview.
            FetchError::Unavailable => ApiError::NotFound("no preview available"),
        }
    }
}

async fn preview(
    AuthedLimited(_ctx): AuthedLimited<LINK_PREVIEW>,
    State(state): State<AppState>,
    Query(params): Query<PreviewParams>,
) -> Result<axum::Json<LinkPreviewDto>, ApiError> {
    let service = state.link_previews.enabled()?;
    // Reject a blocked or malformed URL before any outbound work.
    validate(&params.url, service.allow_private)
        .map_err(|_| ApiError::BadRequest("that link cannot be previewed"))?;

    if let Some(cached) = service.cache.preview(&params.url) {
        return Ok(axum::Json(to_dto(&params.url, cached)));
    }
    let preview = fetch_preview(&service.client, &params.url, service.allow_private)
        .await?
        .ok_or(ApiError::NotFound("no preview available"))?;
    let cached = service.cache.insert(&params.url, preview);
    Ok(axum::Json(to_dto(&params.url, cached)))
}

async fn image(
    AuthedLimited(_ctx): AuthedLimited<ASSET>,
    State(state): State<AppState>,
    Path(token): Path<String>,
) -> Result<Response, ApiError> {
    let service = state.link_previews.enabled()?;
    if let Some((bytes, _)) = service.cache.image_bytes(&token) {
        return serve_image(bytes);
    }
    let url = service.cache.image_url(&token).ok_or(ApiError::NotFound(
        "that preview image is no longer available",
    ))?;
    let (bytes, _) = fetch_image(&service.client, &url, service.allow_private).await?;
    service
        .cache
        .store_image_bytes(&token, bytes.clone(), String::new());
    serve_image(bytes)
}

/// Serves proxied image bytes with a content type sniffed from the bytes
/// themselves, never the upstream header, and `nosniff` so a browser cannot
/// be talked into treating a mislabelled body as HTML.
fn serve_image(bytes: Vec<u8>) -> Result<Response, ApiError> {
    let content_type = media::sniff_content_type(&bytes).ok_or(ApiError::Unavailable)?;
    if !content_type.starts_with("image/") {
        return Err(ApiError::Unavailable);
    }
    let mut response = Response::new(axum::body::Body::from(bytes));
    let headers = response.headers_mut();
    headers.insert(header::CONTENT_TYPE, HeaderValue::from_static(content_type));
    headers.insert(
        header::X_CONTENT_TYPE_OPTIONS,
        HeaderValue::from_static("nosniff"),
    );
    headers.insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("private, max-age=1800"),
    );
    Ok(response)
}
