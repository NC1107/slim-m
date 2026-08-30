-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- The server's long-lived Ed25519 identity keypair, generated once on first
-- boot and never rotated. See src/identity.rs for exactly what a client can
-- and cannot conclude from it.
--
-- Its own table with a CHECK-enforced singleton row, rather than another
-- server_meta key/value pair: a keypair is binary key material with a fixed
-- shape, not a string, and giving it a real column each makes the 32-byte
-- length assumption in src/identity.rs an enforceable schema fact instead of
-- something only application code remembers.
CREATE TABLE server_identity (
    id         INTEGER PRIMARY KEY CHECK (id = 1),
    secret_key BLOB NOT NULL CHECK (length(secret_key) = 32),
    public_key BLOB NOT NULL CHECK (length(public_key) = 32),
    created_at INTEGER NOT NULL
) STRICT;

-- This deployment's display name, shown to a prospective joiner (invite
-- metadata) before they have an account. server_meta already exists as a
-- generic singleton settings table (migration 0001), so a new key here is a
-- real, persisted field rather than a value invented in application code;
-- an admin without a dedicated settings endpoint yet can still change it by
-- updating this row directly. INSERT OR IGNORE so re-running migrations in
-- a fresh database seeds it exactly once.
INSERT OR IGNORE INTO server_meta (key, value) VALUES ('deployment_name', 'slim-m');
