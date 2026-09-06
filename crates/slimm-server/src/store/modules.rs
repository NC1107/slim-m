// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Installed-module persistence: install (metadata plus the permissions it
//! declares), enable/disable, list, and uninstall. No runtime lives here;
//! see docs/decisions/0021-modules-and-the-dock.md for the phasing this is
//! the Phase 2 half of.
//!
//! Artifact bytes are never fetched or stored by this module: `Dock::install`
//! records only the manifest's own metadata, `artifact_sha256` included, as a
//! placeholder a later phase compares real downloaded bytes against. See
//! `http::dock`'s install handler for why that is deliberate at this phase.

use super::{Store, now_ms};

/// One installed module, as recorded at its last install.
#[derive(Debug, Clone)]
pub struct InstalledModule {
    pub id: String,
    pub name: String,
    pub version: String,
    pub artifact_sha256: String,
    pub approved_capabilities: Vec<String>,
    pub enabled: bool,
    pub installed_at: i64,
}

/// One permission a module's manifest declares, as install registers it into
/// `module_permissions`.
pub struct ModulePermissionSpec<'a> {
    pub key: &'a str,
    pub name: &'a str,
    pub description: &'a str,
}

/// Everything an install call needs, bundled so `Store::install_module` stays
/// under the project's 7-positional-parameter limit.
pub struct InstallModuleRequest<'a> {
    pub id: &'a str,
    pub name: &'a str,
    pub version: &'a str,
    pub artifact_sha256: &'a str,
    pub approved_capabilities: &'a [String],
    pub permissions: &'a [ModulePermissionSpec<'a>],
}

struct ModuleRow {
    id: String,
    name: String,
    version: String,
    artifact_sha256: String,
    approved_capabilities: String,
    enabled: bool,
    installed_at: i64,
}

impl From<ModuleRow> for InstalledModule {
    fn from(row: ModuleRow) -> Self {
        // A parse failure means the row was corrupted elsewhere; fall back to empty rather than erroring a read.
        let approved_capabilities =
            serde_json::from_str(&row.approved_capabilities).unwrap_or_default();
        Self {
            id: row.id,
            name: row.name,
            version: row.version,
            artifact_sha256: row.artifact_sha256,
            approved_capabilities,
            enabled: row.enabled,
            installed_at: row.installed_at,
        }
    }
}

impl Store {
    /// Installs (or reinstalls, at a possibly new version) a module.
    ///
    /// Idempotent by `id`: an existing row's metadata is overwritten with
    /// the freshly fetched manifest's, and `enabled` is left untouched by
    /// the `ON CONFLICT` clause - a reinstall must never silently flip a
    /// module back on. `module_permissions` is reconciled rather than
    /// replaced wholesale: a permission key the new manifest still declares
    /// keeps its row (and so keeps every role grant on it, which cascades
    /// away only when the row itself is deleted), while one the manifest
    /// dropped is deleted, cascading its grants with it. Delete-then-reinsert
    /// for every key would cascade away every grant on every reinstall, even
    /// when nothing about that permission changed.
    pub async fn install_module(
        &self,
        req: InstallModuleRequest<'_>,
    ) -> anyhow::Result<InstalledModule> {
        let mut tx = self.begin_write().await?;
        let now = now_ms();
        let caps_json = serde_json::to_string(req.approved_capabilities)?;

        sqlx::query!(
            "INSERT INTO installed_modules
                 (id, name, version, artifact_sha256, approved_capabilities, enabled, installed_at)
             VALUES (?, ?, ?, ?, ?, 0, ?)
             ON CONFLICT(id) DO UPDATE SET
                 name = excluded.name,
                 version = excluded.version,
                 artifact_sha256 = excluded.artifact_sha256,
                 approved_capabilities = excluded.approved_capabilities",
            req.id,
            req.name,
            req.version,
            req.artifact_sha256,
            caps_json,
            now
        )
        .execute(&mut *tx)
        .await?;

        let existing_keys: Vec<String> = sqlx::query_scalar!(
            "SELECT perm_key FROM module_permissions WHERE module_id = ?",
            req.id
        )
        .fetch_all(&mut *tx)
        .await?;
        for key in existing_keys {
            if !req.permissions.iter().any(|p| p.key == key) {
                sqlx::query!(
                    "DELETE FROM module_permissions WHERE module_id = ? AND perm_key = ?",
                    req.id,
                    key
                )
                .execute(&mut *tx)
                .await?;
            }
        }
        for perm in req.permissions {
            sqlx::query!(
                "INSERT INTO module_permissions (module_id, perm_key, name, description)
                 VALUES (?, ?, ?, ?)
                 ON CONFLICT(module_id, perm_key) DO UPDATE SET
                     name = excluded.name, description = excluded.description",
                req.id,
                perm.key,
                perm.name,
                perm.description
            )
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;
        self.installed_module(req.id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("install of {} did not persist", req.id))
    }

    /// One installed module, or `None` if it is not (or no longer) installed.
    pub async fn installed_module(&self, id: &str) -> anyhow::Result<Option<InstalledModule>> {
        let row = sqlx::query_as!(
            ModuleRow,
            r#"SELECT id AS "id!", name AS "name!", version AS "version!",
                      artifact_sha256 AS "artifact_sha256!",
                      approved_capabilities AS "approved_capabilities!",
                      enabled AS "enabled!: bool", installed_at AS "installed_at!"
               FROM installed_modules WHERE id = ?"#,
            id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(InstalledModule::from))
    }

    /// Every installed module, most recently installed first.
    pub async fn list_installed_modules(&self) -> anyhow::Result<Vec<InstalledModule>> {
        let rows = sqlx::query_as!(
            ModuleRow,
            r#"SELECT id AS "id!", name AS "name!", version AS "version!",
                      artifact_sha256 AS "artifact_sha256!",
                      approved_capabilities AS "approved_capabilities!",
                      enabled AS "enabled!: bool", installed_at AS "installed_at!"
               FROM installed_modules ORDER BY installed_at DESC"#
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows.into_iter().map(InstalledModule::from).collect())
    }

    /// Enables or disables an installed module. `Ok(false)` if it is not
    /// installed, so the caller can 404 rather than silently no-op.
    pub async fn set_module_enabled(&self, id: &str, enabled: bool) -> anyhow::Result<bool> {
        let enabled_bit = i64::from(enabled);
        let affected = sqlx::query!(
            "UPDATE installed_modules SET enabled = ? WHERE id = ?",
            enabled_bit,
            id
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        Ok(affected > 0)
    }

    /// Uninstalls a module. `Ok(false)` if it was not installed. The
    /// `module_permissions` and `role_module_permissions` rows cascade away
    /// on the `installed_modules` foreign key, so nothing dangles: see the
    /// migration's own comment.
    pub async fn uninstall_module(&self, id: &str) -> anyhow::Result<bool> {
        let affected = sqlx::query!("DELETE FROM installed_modules WHERE id = ?", id)
            .execute(&self.pool)
            .await?
            .rows_affected();
        Ok(affected > 0)
    }
}
