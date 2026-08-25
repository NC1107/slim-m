-- Adds a deployment-configurable per-channel canvas object cap to the
-- space_settings singleton.
--
-- The default matches MAX_OBJECTS_PER_CHANNEL in
-- crates/slimm-server/src/store/canvas_geometry.rs, so a deployment that
-- predates this setting keeps the exact limit it already enforced; a test
-- pins the two together so they cannot drift.
--
-- Only the lower bound is a CHECK. The settable range (a sane floor and a
-- ceiling that keeps one admin from letting canvases grow big enough to tank
-- every client) is enforced in Rust in set_canvas_object_cap, the same split
-- message_retention_days uses: the DB guards the invariant, Rust guards the
-- policy.
ALTER TABLE space_settings ADD COLUMN canvas_object_cap INTEGER NOT NULL DEFAULT 20000
    CHECK (canvas_object_cap >= 1);
