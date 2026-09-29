-- SPDX-License-Identifier: AGPL-3.0-only
-- Turns on the mediated host capabilities of docs/decisions/0023 for real.
--
-- approved_host_capabilities is what an admin explicitly approved at install,
-- kept apart from approved_capabilities (the manifest's whole declared list,
-- recorded since 0064). A module installed before this migration therefore
-- starts with no host capability, whatever its manifest declares.
ALTER TABLE installed_modules
    ADD COLUMN approved_host_capabilities TEXT NOT NULL DEFAULT '[]';

-- `kv.store`: one bounded key-value space per module. The cascade is what
-- wipes a module's data on uninstall; a reinstall upserts the module row in
-- place, so the data survives it.
CREATE TABLE module_kv (
    module_id TEXT NOT NULL REFERENCES installed_modules(id) ON DELETE CASCADE,
    key       TEXT NOT NULL,
    value     TEXT NOT NULL,
    PRIMARY KEY (module_id, key)
) STRICT;

-- Which module posted a message through `message.post`. Deliberately no
-- foreign key to installed_modules: the attribution outlives an uninstall.
CREATE TABLE module_message_origins (
    message_id BLOB PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
    module_id  TEXT NOT NULL
) STRICT;
