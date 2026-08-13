// SPDX-License-Identifier: AGPL-3.0-only
//! Request-building and response-parsing for each supported GIF provider.
//!
//! Tenor's shape here is pinned against its own published v2 API docs and
//! exercised in tests against a fixture shaped exactly like a real response.
//! Klipy's is modeled on public third-party documentation of its API (Klipy's
//! own `docs.klipy.com` blocks automated fetches, so nothing here was checked
//! against a live account or a captured real response) - the same
//! "reasoned from documentation, not confirmed live" bar this project already
//! carries for platform paths nobody here can run. If a real Klipy account
//! ever surfaces a shape mismatch, this is the one file that needs to change.

use serde::Deserialize;

/// One search result, provider-shape already stripped away: a title and the
/// two upstream CDN URLs a caller may later fetch through, never handed to a
/// client directly (see the parent module's doc comment for why).
pub(super) struct ProviderGif {
    pub(super) title: String,
    pub(super) preview_url: String,
    pub(super) full_url: String,
    /// The full-resolution image's own dimensions, or `(0, 0)` when a
    /// provider's response shape does not carry them (Klipy's documented
    /// shape does not); a client falls back to a fixed aspect ratio for
    /// those rather than treating zero as a real answer.
    pub(super) width: u32,
    pub(super) height: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum Provider {
    Tenor,
    Klipy,
}

impl Provider {
    /// Case-insensitive, matching `SLIMM_GIF_PROVIDER`'s own doc comment.
    pub(super) fn parse(raw: &str) -> Option<Self> {
        match raw.to_ascii_lowercase().as_str() {
            "tenor" => Some(Provider::Tenor),
            "klipy" => Some(Provider::Klipy),
            _ => None,
        }
    }
}

/// Most results a single search asks a provider for; also this module's own
/// ceiling on what it will ever request, independent of whatever a caller
/// passed in.
pub(super) const MAX_LIMIT: u32 = 50;

/// `base_url` overrides each provider's real endpoint host, `None` in every
/// real deployment. It exists so a test can point this at a fake local
/// server rather than a live provider - production code never sets it, and
/// [`super::GifSearch::new`] never accepts one from configuration.
pub(super) async fn search(
    http: &reqwest::Client,
    provider: Provider,
    base_url: Option<&str>,
    api_key: &str,
    query: &str,
    limit: u32,
) -> anyhow::Result<Vec<ProviderGif>> {
    let limit = limit.clamp(1, MAX_LIMIT);
    match provider {
        Provider::Tenor => {
            let url = base_url.unwrap_or(TENOR_SEARCH_URL);
            search_tenor(http, url, api_key, query, limit).await
        }
        Provider::Klipy => {
            let base = base_url.unwrap_or(KLIPY_BASE_URL);
            search_klipy(http, base, api_key, query, limit).await
        }
    }
}

const TENOR_SEARCH_URL: &str = "https://tenor.googleapis.com/v2/search";
const KLIPY_BASE_URL: &str = "https://api.klipy.com";

#[derive(Deserialize)]
struct TenorResponse {
    results: Vec<TenorResult>,
}

#[derive(Deserialize)]
struct TenorResult {
    #[serde(default)]
    content_description: String,
    media_formats: TenorMediaFormats,
}

#[derive(Deserialize)]
struct TenorMediaFormats {
    tinygif: Option<TenorMedia>,
    gif: Option<TenorMedia>,
}

#[derive(Deserialize)]
struct TenorMedia {
    url: String,
    dims: [u32; 2],
}

/// One result needs `tinygif` for a preview and `gif` for the eventual
/// attachment; either standing in for the other when only one is present
/// keeps a result usable rather than dropping it outright, and a result
/// carrying neither is dropped, since there is nothing to show or store.
fn tenor_result_into_gif(result: TenorResult) -> Option<ProviderGif> {
    let preview = result
        .media_formats
        .tinygif
        .as_ref()
        .or(result.media_formats.gif.as_ref())?;
    let full = result
        .media_formats
        .gif
        .as_ref()
        .or(result.media_formats.tinygif.as_ref())?;
    Some(ProviderGif {
        title: result.content_description,
        preview_url: preview.url.clone(),
        full_url: full.url.clone(),
        width: full.dims[0],
        height: full.dims[1],
    })
}

async fn search_tenor(
    http: &reqwest::Client,
    url: &str,
    api_key: &str,
    query: &str,
    limit: u32,
) -> anyhow::Result<Vec<ProviderGif>> {
    let limit_str = limit.to_string();
    let response = http
        .get(url)
        .query(&[
            ("q", query),
            ("key", api_key),
            ("client_key", "slim-m"),
            ("limit", &limit_str),
            ("media_filter", "tinygif,gif"),
            ("contentfilter", "medium"),
        ])
        .send()
        .await?
        .error_for_status()?;
    let parsed: TenorResponse = response.json().await?;
    Ok(parsed
        .results
        .into_iter()
        .filter_map(tenor_result_into_gif)
        .collect())
}

#[derive(Deserialize)]
struct KlipyResponse {
    data: KlipyPage,
}

#[derive(Deserialize)]
struct KlipyPage {
    data: Vec<KlipyItem>,
}

#[derive(Deserialize)]
struct KlipyItem {
    #[serde(default)]
    title: String,
    files: KlipyFiles,
}

#[derive(Deserialize)]
struct KlipyFiles {
    preview: Option<String>,
    gif: Option<String>,
    webp: Option<String>,
}

fn klipy_item_into_gif(item: KlipyItem) -> Option<ProviderGif> {
    Some(ProviderGif {
        title: item.title,
        preview_url: item.files.preview?,
        full_url: item.files.gif.or(item.files.webp)?,
        // Not carried in the documented shape; see this module's own doc comment.
        width: 0,
        height: 0,
    })
}

async fn search_klipy(
    http: &reqwest::Client,
    base: &str,
    api_key: &str,
    query: &str,
    limit: u32,
) -> anyhow::Result<Vec<ProviderGif>> {
    let url = format!("{base}/api/v1/{api_key}/gifs/search");
    let limit_str = limit.to_string();
    let response = http
        .get(url)
        .query(&[("q", query), ("page", "1"), ("per_page", &limit_str)])
        .send()
        .await?
        .error_for_status()?;
    let parsed: KlipyResponse = response.json().await?;
    Ok(parsed
        .data
        .data
        .into_iter()
        .filter_map(klipy_item_into_gif)
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_parse_is_case_insensitive_and_rejects_unknown() {
        assert_eq!(Provider::parse("tenor"), Some(Provider::Tenor));
        assert_eq!(Provider::parse("Tenor"), Some(Provider::Tenor));
        assert_eq!(Provider::parse("TENOR"), Some(Provider::Tenor));
        assert_eq!(Provider::parse("klipy"), Some(Provider::Klipy));
        assert_eq!(Provider::parse("Klipy"), Some(Provider::Klipy));
        assert_eq!(Provider::parse("giphy"), None);
        assert_eq!(Provider::parse(""), None);
    }

    /// Shaped exactly like Tenor's own documented v2 `/search` response
    /// (`next`, `results[].id`, `media_formats.{tinygif,gif}.{url,dims,size}`),
    /// so a change to `tenor_result_into_gif` that stops matching it fails
    /// here rather than only against a live key nothing in CI has.
    #[test]
    fn tenor_result_prefers_tinygif_for_preview_and_gif_for_full() {
        let raw = r#"{
            "next": "",
            "results": [
                {
                    "id": "12345",
                    "content_description": "a cat waving",
                    "media_formats": {
                        "tinygif": {"url": "https://tenor.example/preview.gif", "dims": [220, 165], "size": 45000},
                        "gif": {"url": "https://tenor.example/full.gif", "dims": [498, 373], "size": 890000}
                    }
                }
            ]
        }"#;
        let parsed: TenorResponse = serde_json::from_str(raw).unwrap();
        let gifs: Vec<ProviderGif> = parsed
            .results
            .into_iter()
            .filter_map(tenor_result_into_gif)
            .collect();
        assert_eq!(gifs.len(), 1);
        assert_eq!(gifs[0].title, "a cat waving");
        assert_eq!(gifs[0].preview_url, "https://tenor.example/preview.gif");
        assert_eq!(gifs[0].full_url, "https://tenor.example/full.gif");
        assert_eq!((gifs[0].width, gifs[0].height), (498, 373));
    }

    /// A result missing both usable formats (a media type this deployment
    /// never asks for, or a provider oddity) is dropped rather than passed
    /// through with an empty URL.
    #[test]
    fn a_tenor_result_with_neither_usable_format_is_dropped() {
        let raw = r#"{
            "next": "",
            "results": [
                {"id": "1", "content_description": "no formats", "media_formats": {}}
            ]
        }"#;
        let parsed: TenorResponse = serde_json::from_str(raw).unwrap();
        let gifs: Vec<ProviderGif> = parsed
            .results
            .into_iter()
            .filter_map(tenor_result_into_gif)
            .collect();
        assert!(gifs.is_empty());
    }

    /// Shaped per this module's own doc comment on how Klipy's response was
    /// modeled: `{"data": {"data": [{"title", "files": {...}}]}}`.
    #[test]
    fn klipy_item_reads_gif_over_webp_when_both_are_present() {
        let raw = r#"{
            "data": {
                "data": [
                    {
                        "title": "a dog nodding",
                        "files": {
                            "preview": "https://klipy.example/preview.webp",
                            "gif": "https://klipy.example/full.gif",
                            "webp": "https://klipy.example/full.webp"
                        }
                    }
                ]
            }
        }"#;
        let parsed: KlipyResponse = serde_json::from_str(raw).unwrap();
        let gifs: Vec<ProviderGif> = parsed
            .data
            .data
            .into_iter()
            .filter_map(klipy_item_into_gif)
            .collect();
        assert_eq!(gifs.len(), 1);
        assert_eq!(gifs[0].title, "a dog nodding");
        assert_eq!(gifs[0].full_url, "https://klipy.example/full.gif");
    }

    /// Klipy without a `gif` field falls back to `webp`, which this
    /// deployment's own attachment allowlist already accepts (see
    /// `media::content_type`), rather than being dropped for lacking the
    /// exact format Tenor happens to use.
    #[test]
    fn klipy_item_falls_back_to_webp_when_gif_is_absent() {
        let raw = r#"{
            "data": {
                "data": [
                    {
                        "title": "webp only",
                        "files": {
                            "preview": "https://klipy.example/preview.webp",
                            "webp": "https://klipy.example/full.webp"
                        }
                    }
                ]
            }
        }"#;
        let parsed: KlipyResponse = serde_json::from_str(raw).unwrap();
        let gifs: Vec<ProviderGif> = parsed
            .data
            .data
            .into_iter()
            .filter_map(klipy_item_into_gif)
            .collect();
        assert_eq!(gifs.len(), 1);
        assert_eq!(gifs[0].full_url, "https://klipy.example/full.webp");
    }
}
