// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The guarded GET behind [`super::ssrf`]: bounded in time (the client's own
//! timeouts) and in body size, so a hostile or slow response cannot tie up
//! the server, the same shape `http::link_preview::fetch` uses for an
//! arbitrary-host fetch.

use reqwest::{Client, StatusCode};
use url::Url;

use super::ssrf::{UrlError, validate};

/// Largest `index.json` this server will read.
pub(super) const MAX_INDEX_BYTES: usize = 256 * 1024;
/// Largest `manifest.json` this server will read.
pub(super) const MAX_MANIFEST_BYTES: usize = 64 * 1024;
/// Largest module artifact this server will fetch and store. A module is
/// pure compute with no wasm imports (see `crate::module_runtime`'s ABI doc),
/// so even a bundled language runtime compiled to wasm is expected to fit
/// well inside this; sized generously above that rather than tightly, since
/// the real ceiling on what a module can do at run time is its own
/// `runtime.limits`, not this fetch cap.
pub(super) const MAX_ARTIFACT_BYTES: usize = 16 * 1024 * 1024;

/// What went wrong fetching from the Dock's one allowed host.
#[derive(Debug, PartialEq, Eq)]
pub(super) enum FetchError {
    /// The URL is not well-formed, or does not point at the allowed host.
    Refused,
    /// A well-formed request to the allowed host that still could not be
    /// completed: unreachable, a non-200 other than [`FetchError::Missing`]'s,
    /// or the body ran over its cap.
    Unavailable,
    /// The host answered that nothing is there: a 404, or a redirect, which
    /// this client never follows. The only error [`fetch_first`] moves past.
    Missing,
}

impl From<UrlError> for FetchError {
    fn from(_: UrlError) -> Self {
        FetchError::Refused
    }
}

/// GETs [url] and returns its body, capped at [cap] bytes. [allowed_host]
/// gates every request through [`super::ssrf::validate`] first.
pub(super) async fn fetch_capped(
    client: &Client,
    url: &Url,
    allowed_host: &str,
    cap: usize,
) -> Result<Vec<u8>, FetchError> {
    validate(url, allowed_host)?;
    let response = client
        .get(url.clone())
        .send()
        .await
        .map_err(|_| FetchError::Unavailable)?;
    let status = response.status();
    if status == StatusCode::NOT_FOUND || status.is_redirection() {
        return Err(FetchError::Missing);
    }
    if status != StatusCode::OK {
        return Err(FetchError::Unavailable);
    }
    read_capped(response, cap).await
}

/// GETs [path] under each of [bases] in turn and returns the first body
/// found, moving on only when a base answers [`FetchError::Missing`]. An
/// outage stops the walk instead, so a down host costs one timeout rather
/// than one per base, and every candidate stays on [allowed_host].
pub(super) async fn fetch_first(
    client: &Client,
    bases: &[Url],
    path: &str,
    allowed_host: &str,
    cap: usize,
) -> Result<Vec<u8>, FetchError> {
    for base in bases {
        let url = base.join(path).map_err(|_| FetchError::Refused)?;
        match fetch_capped(client, &url, allowed_host, cap).await {
            Err(FetchError::Missing) => continue,
            found => return found,
        }
    }
    Err(FetchError::Missing)
}

/// Reads at most [cap] bytes from [response], stopping the moment the body
/// runs over rather than buffering an unbounded one.
async fn read_capped(mut response: reqwest::Response, cap: usize) -> Result<Vec<u8>, FetchError> {
    let mut body = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|_| FetchError::Unavailable)?
    {
        if body.len() + chunk.len() > cap {
            return Err(FetchError::Unavailable);
        }
        body.extend_from_slice(&chunk);
    }
    Ok(body)
}
