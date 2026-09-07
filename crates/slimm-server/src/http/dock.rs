// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The Dock: browsing and installing modules from the addons repo, per
//! docs/decisions/0021-modules-and-the-dock.md. Gated on MANAGE_SERVER, the
//! same bit as `/space/analytics` and `/space/storage`, since it lives under
//! Space settings alongside them.
//!
//! Phase 1 (browse) and Phase 2 (install/enable/uninstall) only: nothing
//! here runs a module, or knows what one does. `manifest.rs` parses and
//! strictly validates what the registry returns; `ssrf.rs` and `fetch.rs`
//! reach it through a host-allowlisted client, the same posture decision
//! 0019 gives link preview's arbitrary-host fetch, narrowed here to the one
//! fixed host this Dock is configured with; `wire.rs` holds the DTOs.

mod fetch;
mod manifest;
mod ssrf;
mod wire;

use std::sync::Arc;

use axum::Router;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{get, post};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use url::Url;

use super::AppState;
use super::error::ApiError;
use super::extract::require_manage_server;
use super::extract::{Authed, Json, enforce};
use crate::config::Config;
use crate::media::to_hex;
use crate::ratelimit::Class;
use crate::store::{
    InstallModuleRequest, ModuleExtensionPointSpec, ModulePermissionSpec, ModuleRuntimeLimits,
};

use fetch::{FetchError, fetch_capped};
use manifest::{Manifest, ManifestError, parse_index, parse_manifest, validate_slug};
use wire::{IndexEntryDto, InstalledModuleDto, ManifestDto};

const BODY_LIMIT: usize = 4 * 1024;

/// The fixed host every Dock fetch targets in production; see
/// `Config::addons_repo`'s own doc for why only the repo is configurable.
const ADDONS_HOST: &str = "raw.githubusercontent.com";

const MAX_MODULE_ID_LEN: usize = 64;

/// This deployment's Dock: cheap to clone (an `Option<Arc<_>>`), the same
/// shape `http::link_preview::LinkPreviews` and `http::gifs::GifSearch` use.
#[derive(Clone)]
pub struct Dock {
    inner: Option<Arc<Enabled>>,
}

struct Enabled {
    client: reqwest::Client,
    base_url: Url,
    allowed_host: String,
}

impl Dock {
    /// Always enabled: unlike link previews, the Dock has no deployment-wide
    /// off switch - `MANAGE_SERVER` alone gates it. Only the repo it points
    /// at is configurable.
    pub fn new(config: &Config) -> Self {
        let base_url = Url::parse(&format!(
            "https://{ADDONS_HOST}/{}/main/",
            config.addons_repo
        ))
        .expect("a fixed host and an operator-provided repo slug always form a valid URL");
        Self {
            inner: Some(Arc::new(Enabled {
                client: ssrf::build_client(false),
                base_url,
                allowed_host: ADDONS_HOST.to_owned(),
            })),
        }
    }

    /// A disabled stand-in for a test building [`AppState`] with no interest
    /// in the Dock: every one of its routes would need a real fetch, so
    /// nothing exercises it by accident.
    pub fn disabled() -> Self {
        Self { inner: None }
    }

    /// An enabled Dock pointed at a local fake upstream, for a test that
    /// drives the real router. [base_url] must end in `/`; its host becomes
    /// the allowlisted one, and the guard resolver allows private addresses
    /// so the loopback a fake upstream binds to is reachable.
    pub fn for_test(base_url: &str) -> Self {
        let parsed = Url::parse(base_url).expect("test base url must parse");
        let allowed_host = parsed
            .host_str()
            .expect("test base url must have a host")
            .to_owned();
        Self {
            inner: Some(Arc::new(Enabled {
                client: ssrf::build_client(true),
                base_url: parsed,
                allowed_host,
            })),
        }
    }

    fn enabled(&self) -> Result<&Enabled, ApiError> {
        self.inner.as_deref().ok_or(ApiError::NotConfigured(
            "the module marketplace is not configured",
        ))
    }
}

/// The Dock routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/space/dock/modules", get(list_modules))
        .route("/space/dock/modules/{id}", get(get_module))
        .route(
            "/space/dock/modules/{id}/install",
            post(install).delete(uninstall),
        )
        .route("/space/dock/modules/{id}/enable", post(enable))
        .route("/space/dock/modules/{id}/disable", post(disable))
        .route("/space/dock/installed", get(list_installed))
        .layer(DefaultBodyLimit::max(BODY_LIMIT))
}

impl From<FetchError> for ApiError {
    fn from(err: FetchError) -> Self {
        match err {
            // Unreachable unless the Dock's own fixed-base URL construction broke, never a caller's doing.
            FetchError::Refused => ApiError::Internal,
            FetchError::Unavailable => ApiError::Unavailable,
        }
    }
}

impl From<ManifestError> for ApiError {
    fn from(err: ManifestError) -> Self {
        match err {
            ManifestError::Malformed(reason) => ApiError::UpstreamInvalid(reason),
        }
    }
}

/// `pub(crate)` rather than `pub(self)`: `http::module_commands` validates a
/// command route's own `moduleId` path segment the same way, and a second
/// slug validator there could silently drift from this one's rules.
pub(crate) fn validate_module_id(id: &str) -> Result<(), ApiError> {
    validate_slug(id, MAX_MODULE_ID_LEN).map_err(|_| ApiError::BadRequest("invalid module id"))
}

/// Fetches and validates the module at [id]'s current `manifest.json`,
/// confirming the registry's own `id` field agrees with the path it was
/// fetched at - the same "does not alias a different resource" check
/// `messages::SendError::IdConflict` exists for elsewhere.
async fn fetch_manifest(dock: &Enabled, id: &str) -> Result<Manifest, ApiError> {
    let url = dock
        .base_url
        .join(&format!("modules/{id}/manifest.json"))
        .map_err(|_| ApiError::Internal)?;
    let bytes = fetch_capped(
        &dock.client,
        &url,
        &dock.allowed_host,
        fetch::MAX_MANIFEST_BYTES,
    )
    .await?;
    let manifest = parse_manifest(&bytes)?;
    if manifest.id != id {
        return Err(ApiError::UpstreamInvalid(
            "manifest.json's own id does not match the module it was fetched for".to_owned(),
        ));
    }
    Ok(manifest)
}

async fn list_modules(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
) -> Result<Json<Vec<IndexEntryDto>>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_server(&state, ctx.user_id).await?;
    let dock = state.dock.enabled()?;
    let url = dock
        .base_url
        .join("index.json")
        .map_err(|_| ApiError::Internal)?;
    let bytes = fetch_capped(
        &dock.client,
        &url,
        &dock.allowed_host,
        fetch::MAX_INDEX_BYTES,
    )
    .await?;
    let index = parse_index(&bytes)?;
    Ok(Json(index.into_iter().map(IndexEntryDto::from).collect()))
}

async fn get_module(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
    Path(id): Path<String>,
) -> Result<Json<ManifestDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_server(&state, ctx.user_id).await?;
    validate_module_id(&id)?;
    let dock = state.dock.enabled()?;
    let manifest = fetch_manifest(dock, &id).await?;
    Ok(Json(ManifestDto::from(manifest)))
}

#[derive(Deserialize)]
struct InstallRequest {
    /// The version the admin reviewed in the Dock before installing. Checked
    /// against the freshly re-fetched manifest's own `version` so a race
    /// with an upstream release cannot install something nobody reviewed.
    version: String,
}

async fn install(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
    Path(id): Path<String>,
    Json(req): Json<InstallRequest>,
) -> Result<Json<InstalledModuleDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_server(&state, ctx.user_id).await?;
    validate_module_id(&id)?;
    let dock = state.dock.enabled()?;
    let manifest = fetch_manifest(dock, &id).await?;
    if manifest.version != req.version {
        return Err(ApiError::Conflict(
            "the module's current version no longer matches the one requested; reopen it in the Dock",
        ));
    }
    let artifact = fetch_artifact(dock, &manifest).await?;

    let permissions: Vec<ModulePermissionSpec> = manifest
        .permissions
        .iter()
        .map(|p| ModulePermissionSpec {
            key: &p.key,
            name: &p.name,
            description: &p.description,
        })
        .collect();
    let extension_points: Vec<ModuleExtensionPointSpec> = manifest
        .extension_points
        .iter()
        .map(|e| ModuleExtensionPointSpec {
            kind: &e.kind,
            name: &e.name,
            description: e.description.as_deref(),
            permission: e.permission.as_deref(),
            command: e.command.as_deref(),
            language: e.language.as_deref(),
        })
        .collect();
    let runtime_limits = ModuleRuntimeLimits {
        memory_mb: manifest.runtime.limits.memory_mb,
        wall_ms: manifest.runtime.limits.wall_ms,
        fuel: manifest.runtime.limits.fuel,
    };
    let installed = state
        .store
        .install_module(InstallModuleRequest {
            id: &manifest.id,
            name: &manifest.name,
            version: &manifest.version,
            artifact_sha256: &manifest.artifact.sha256,
            approved_capabilities: &manifest.capabilities,
            runtime_limits: &runtime_limits,
            permissions: &permissions,
            extension_points: &extension_points,
        })
        .await?;
    state
        .store
        .store_module_artifact(&manifest.id, &manifest.artifact.sha256, &artifact)
        .await?;
    Ok(Json(InstalledModuleDto::from(installed)))
}

/// Fetches the module's own artifact bytes at `manifest.artifact.path`,
/// relative to the same allowlisted base the manifest itself came from, and
/// refuses them if their sha256 does not match what the manifest declared -
/// the fetch-time half of the check `crate::module_runtime::ModuleHost`
/// repeats again, defense in depth, right before it ever runs them.
async fn fetch_artifact(dock: &Enabled, manifest: &Manifest) -> Result<Vec<u8>, ApiError> {
    let url = dock
        .base_url
        .join(&manifest.artifact.path)
        .map_err(|_| ApiError::Internal)?;
    let bytes = fetch_capped(
        &dock.client,
        &url,
        &dock.allowed_host,
        fetch::MAX_ARTIFACT_BYTES,
    )
    .await?;
    let digest = to_hex(&Sha256::digest(&bytes));
    if digest != manifest.artifact.sha256 {
        return Err(ApiError::UpstreamInvalid(
            "the module artifact's sha256 does not match its manifest".to_owned(),
        ));
    }
    Ok(bytes)
}

async fn uninstall(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
    Path(id): Path<String>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_server(&state, ctx.user_id).await?;
    if state.store.uninstall_module(&id).await? {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(ApiError::NotFound("module not installed"))
    }
}

async fn enable(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
    Path(id): Path<String>,
) -> Result<Json<InstalledModuleDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_server(&state, ctx.user_id).await?;
    apply_enabled(&state, &id, true).await
}

async fn disable(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
    Path(id): Path<String>,
) -> Result<Json<InstalledModuleDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    require_manage_server(&state, ctx.user_id).await?;
    apply_enabled(&state, &id, false).await
}

/// The shared body of [`enable`] and [`disable`] once the caller is already
/// authorized: each keeps its own `enforce`/`require_manage_server` call so
/// `tests/openapi_429_coverage.rs`'s static scan, which reads a handler's own
/// body rather than following calls it makes, still sees the charge.
async fn apply_enabled(
    state: &AppState,
    id: &str,
    enabled: bool,
) -> Result<Json<InstalledModuleDto>, ApiError> {
    if !state.store.set_module_enabled(id, enabled).await? {
        return Err(ApiError::NotFound("module not installed"));
    }
    let installed = state
        .store
        .installed_module(id)
        .await?
        .ok_or(ApiError::NotFound("module not installed"))?;
    Ok(Json(InstalledModuleDto::from(installed)))
}

async fn list_installed(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
) -> Result<Json<Vec<InstalledModuleDto>>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::AuthedRead)?;
    require_manage_server(&state, ctx.user_id).await?;
    let modules = state.store.list_installed_modules().await?;
    Ok(Json(
        modules.into_iter().map(InstalledModuleDto::from).collect(),
    ))
}
