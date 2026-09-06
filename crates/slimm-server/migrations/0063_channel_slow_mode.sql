-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Per-channel slow mode: the minimum interval, in seconds, a non-exempt
-- member must wait between their own messages in this channel. 0 (the
-- default, and what every channel created before this migration keeps) means
-- off. Only the lower bound is a CHECK; the settable ceiling
-- (SLOW_MODE_MAX_SECONDS) is enforced in Rust, the same split
-- screen_share_max_height and canvas_object_cap use: the DB guards the
-- invariant, Rust guards the policy, so the ceiling can move without a
-- migration.
ALTER TABLE channels ADD COLUMN slow_mode_seconds INTEGER NOT NULL DEFAULT 0
    CHECK (slow_mode_seconds >= 0);
