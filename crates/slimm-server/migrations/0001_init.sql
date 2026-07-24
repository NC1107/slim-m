-- SPDX-License-Identifier: AGPL-3.0-only
-- Phase 0 places only a marker table so the migration runner is exercised
-- end to end. The real schema (users, channels, messages, RBAC, canvas
-- objects, per-scope sequence counters) lands in Phase 1.

CREATE TABLE IF NOT EXISTS server_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

INSERT OR IGNORE INTO server_meta (key, value) VALUES ('schema_phase', '0');
