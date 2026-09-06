// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The Dock's full documented surface: browse the marketplace, install,
//! enable, disable and uninstall a module, and grant/revoke the permission
//! it registers. The fake registry `world.rs` stands up serves one module,
//! `code-exec`, with the real shape (see docs/decisions/0021), so every call
//! here reaches a genuine 2xx rather than a 501 or 502.

use serde_json::json;

use super::text;
use crate::world::Contract;

pub(super) async fn dock_calls(c: &mut Contract, root: &str) {
    let modules = c.get("listDockModules", "/space/dock/modules", root).await;
    let id = text(&modules.as_array().expect("an array")[0], "id");

    let manifest = c
        .get("getDockModule", &format!("/space/dock/modules/{id}"), root)
        .await;
    let version = text(&manifest, "version");

    c.json(
        "installDockModule",
        "POST",
        &format!("/space/dock/modules/{id}/install"),
        root,
        json!({ "version": version }),
    )
    .await;

    c.get("listInstalledDockModules", "/space/dock/installed", root)
        .await;
    c.bare(
        "enableDockModule",
        "POST",
        &format!("/space/dock/modules/{id}/enable"),
        root,
    )
    .await;
    c.bare(
        "disableDockModule",
        "POST",
        &format!("/space/dock/modules/{id}/disable"),
        root,
    )
    .await;

    c.get("listModulePermissions", "/roles/module-permissions", root)
        .await;

    let role = c
        .json(
            "createRole",
            "POST",
            "/roles",
            root,
            json!({ "name": "dock-testers", "permissions": 0 }),
        )
        .await;
    let role_id = text(&role, "id");

    c.get(
        "listRoleModulePermissions",
        &format!("/roles/{role_id}/module-permissions"),
        root,
    )
    .await;
    c.bare(
        "grantModulePermission",
        "PUT",
        &format!("/roles/{role_id}/module-permissions/{id}/run"),
        root,
    )
    .await;
    c.bare(
        "revokeModulePermission",
        "DELETE",
        &format!("/roles/{role_id}/module-permissions/{id}/run"),
        root,
    )
    .await;
    c.bare("deleteRole", "DELETE", &format!("/roles/{role_id}"), root)
        .await;

    c.bare(
        "uninstallDockModule",
        "DELETE",
        &format!("/space/dock/modules/{id}/install"),
        root,
    )
    .await;
}
