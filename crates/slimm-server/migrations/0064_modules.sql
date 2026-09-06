-- SPDX-License-Identifier: AGPL-3.0-only
-- The module system foundation: Phase 1 (Dock browse) needs no schema of its
-- own - it only fetches and parses the addons repo's index and manifests -
-- so this migration is entirely Phase 2 (install + dynamic permissions), per
-- docs/decisions/0021-modules-and-the-dock.md. No runtime lives here or
-- anywhere else yet: this only records what is installed and who may use
-- what it declares.
--
-- One deployment is one Space (see CLAUDE.md), so none of these three tables
-- carry a space_id, the same reasoning space_settings is a single row.
--
-- installed_modules.id is the module id from its manifest.json (a slug like
-- "code-exec"), not a minted UUIDv7: it is identity handed to us by the
-- addons repo, not identity this server assigns. artifact_sha256 is recorded
-- from the manifest as metadata now; nothing here fetches or verifies the
-- artifact bytes themselves yet; a later phase that fetches
-- runtime.backend's artifact checks the bytes against this column, and Phase
-- 2's own manifest validation already refuses anything that is not a
-- 64-character hex string.
CREATE TABLE installed_modules (
    id                    TEXT PRIMARY KEY,
    name                  TEXT NOT NULL,
    version               TEXT NOT NULL,
    artifact_sha256       TEXT NOT NULL,
    -- The manifest's declared `capabilities`, approved as a whole at install
    -- time (see http::dock's install handler); a JSON array of strings
    -- rather than a side table, since nothing here queries into it - a
    -- module host reads the whole list at once, the same shape
    -- approved_capabilities always take.
    approved_capabilities TEXT NOT NULL DEFAULT '[]',
    enabled               INTEGER NOT NULL DEFAULT 0 CHECK (enabled IN (0, 1)),
    installed_at          INTEGER NOT NULL
) STRICT;

-- A module's declared permissions, registered at install time from its
-- manifest and re-synced on every reinstall (a version bump can add, drop,
-- or reword one). This is the dynamic half of the permission model decision
-- 0021 asks for: named, module-scoped permission rows a role can hold,
-- without slim's core Permissions bitmask ever knowing they exist.
CREATE TABLE module_permissions (
    module_id   TEXT NOT NULL REFERENCES installed_modules(id) ON DELETE CASCADE,
    perm_key    TEXT NOT NULL,
    name        TEXT NOT NULL,
    description TEXT NOT NULL,
    PRIMARY KEY (module_id, perm_key)
) STRICT;

-- Which role holds which module permission, the module-scoped parallel to
-- `roles.permissions`'s bitmask for core permissions. The composite foreign
-- key to module_permissions means uninstalling a module, or a reinstall that
-- drops a permission the manifest no longer declares, cascades the grant
-- away with it - nothing here can outlive the permission it grants.
CREATE TABLE role_module_permissions (
    role_id   BLOB NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    module_id TEXT NOT NULL,
    perm_key  TEXT NOT NULL,
    PRIMARY KEY (role_id, module_id, perm_key),
    FOREIGN KEY (module_id, perm_key)
        REFERENCES module_permissions(module_id, perm_key) ON DELETE CASCADE
) STRICT;

-- The read Store::user_has_module_permission runs: every role that holds one
-- given (module_id, perm_key).
CREATE INDEX role_module_permissions_lookup ON role_module_permissions(module_id, perm_key);
