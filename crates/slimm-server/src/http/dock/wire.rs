// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Wire DTOs for the Dock's HTTP surface, kept apart from `dock.rs`'s
//! handlers and `manifest.rs`'s parsing purely to hold the file budget - see
//! `http::link_preview`'s own split for the precedent.

use serde::Serialize;

use super::manifest::{IndexEntry, Manifest};
use crate::store::InstalledModule;

#[derive(Serialize)]
pub(super) struct IndexEntryDto {
    id: String,
    name: String,
    version: String,
    summary: String,
}

impl From<IndexEntry> for IndexEntryDto {
    fn from(entry: IndexEntry) -> Self {
        Self {
            id: entry.id,
            name: entry.name,
            version: entry.version,
            summary: entry.summary,
        }
    }
}

#[derive(Serialize)]
pub(super) struct ArtifactDto {
    kind: String,
    path: String,
    sha256: String,
}

#[derive(Serialize)]
pub(super) struct LimitsDto {
    memory_mb: Option<u64>,
    wall_ms: Option<u64>,
    fuel: Option<u64>,
}

#[derive(Serialize)]
pub(super) struct RuntimeDto {
    backend: String,
    limits: LimitsDto,
}

#[derive(Serialize)]
pub(super) struct PermissionDto {
    key: String,
    name: String,
    description: String,
}

#[derive(Serialize)]
pub(super) struct ExtensionPointDto {
    kind: String,
    name: String,
    description: Option<String>,
    permission: Option<String>,
}

/// A module's full manifest, as the Dock shows an admin before install: every
/// permission it will add and every capability it asks for.
#[derive(Serialize)]
pub(super) struct ManifestDto {
    id: String,
    name: String,
    version: String,
    summary: String,
    author: Option<String>,
    artifact: ArtifactDto,
    runtime: RuntimeDto,
    permissions: Vec<PermissionDto>,
    capabilities: Vec<String>,
    extension_points: Vec<ExtensionPointDto>,
}

impl From<Manifest> for ManifestDto {
    fn from(m: Manifest) -> Self {
        Self {
            id: m.id,
            name: m.name,
            version: m.version,
            summary: m.summary,
            author: m.author,
            artifact: ArtifactDto {
                kind: m.artifact.kind,
                path: m.artifact.path,
                sha256: m.artifact.sha256,
            },
            runtime: RuntimeDto {
                backend: m.runtime.backend,
                limits: LimitsDto {
                    memory_mb: m.runtime.limits.memory_mb,
                    wall_ms: m.runtime.limits.wall_ms,
                    fuel: m.runtime.limits.fuel,
                },
            },
            permissions: m
                .permissions
                .into_iter()
                .map(|p| PermissionDto {
                    key: p.key,
                    name: p.name,
                    description: p.description,
                })
                .collect(),
            capabilities: m.capabilities,
            extension_points: m
                .extension_points
                .into_iter()
                .map(|e| ExtensionPointDto {
                    kind: e.kind,
                    name: e.name,
                    description: e.description,
                    permission: e.permission,
                })
                .collect(),
        }
    }
}

/// One installed module, as `GET /space/dock/installed` and every lifecycle
/// verb answer with. `extension_points` is surfaced here (rather than only
/// in the pre-install `ManifestDto`) so a client can discover which commands
/// an already-installed module offers, and which permission each needs,
/// without re-browsing the Dock.
#[derive(Serialize)]
pub(super) struct InstalledModuleDto {
    id: String,
    name: String,
    version: String,
    artifact_sha256: String,
    approved_capabilities: Vec<String>,
    extension_points: Vec<ExtensionPointDto>,
    enabled: bool,
    installed_at: i64,
}

impl From<InstalledModule> for InstalledModuleDto {
    fn from(m: InstalledModule) -> Self {
        Self {
            id: m.id,
            name: m.name,
            version: m.version,
            artifact_sha256: m.artifact_sha256,
            approved_capabilities: m.approved_capabilities,
            extension_points: m
                .extension_points
                .into_iter()
                .map(|e| ExtensionPointDto {
                    kind: e.kind,
                    name: e.name,
                    description: e.description,
                    permission: e.permission,
                })
                .collect(),
            enabled: m.enabled,
            installed_at: m.installed_at,
        }
    }
}
