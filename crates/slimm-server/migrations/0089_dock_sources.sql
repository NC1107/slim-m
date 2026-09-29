-- SPDX-License-Identifier: AGPL-3.0-only
-- Extra module sources beside the official one, per docs/decisions/0046.
--
-- repo is an owner/repo slug served from the Dock's one fixed host, never a
-- URL. Nothing here names the official source: it comes from configuration.
CREATE TABLE dock_sources (
    id         TEXT PRIMARY KEY,
    repo       TEXT NOT NULL COLLATE NOCASE UNIQUE,
    created_at INTEGER NOT NULL
) STRICT;

-- The repo an installed module came from, kept as text rather than a foreign
-- key so removing a source leaves its modules installed and still labelled.
-- NULL is the official source, including every module installed before this.
ALTER TABLE installed_modules ADD COLUMN source_repo TEXT;
