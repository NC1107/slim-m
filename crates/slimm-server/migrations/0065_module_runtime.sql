-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Phase 3 (the module host and wasm backend), docs/decisions/0021-modules-and-the-dock.md.
--
-- installed_modules gains two more JSON columns, the same shape
-- approved_capabilities already uses in 0064: runtime_limits (the manifest's
-- runtime.limits, so the host enforces a memory/fuel/wall-clock cap without
-- reaching the addons repo again at command time) and extension_points (each
-- one's kind, name, and - for a command - the permission key it requires).
-- Both are the persisted half of what 0064 left to the Dock's own in-memory
-- fetch: a manifest is only ever fetched at install time, so anything the
-- runtime needs later has to be recorded here.
ALTER TABLE installed_modules ADD COLUMN runtime_limits TEXT NOT NULL DEFAULT '{}';
ALTER TABLE installed_modules ADD COLUMN extension_points TEXT NOT NULL DEFAULT '[]';

-- The module's own wasm bytes, fetched over the Dock's guarded client and
-- sha256-verified against the manifest at install time, then never fetched
-- again: the runtime reads them from here on every command call.
--
-- Kept as a row rather than a media-style file on purpose, unlike
-- attachments (see src/media/mod.rs): a module artifact is one of a handful
-- an admin installs deployment-wide, not one of thousands of member
-- uploads, its size is bounded at fetch time, and it is versioned together
-- with the install row it belongs to - there is no attachment-shaped growth
-- or backup argument for keeping it out of the database file here.
CREATE TABLE module_artifacts (
    module_id TEXT PRIMARY KEY REFERENCES installed_modules(id) ON DELETE CASCADE,
    sha256    TEXT NOT NULL,
    bytes     BLOB NOT NULL,
    stored_at INTEGER NOT NULL
) STRICT;
