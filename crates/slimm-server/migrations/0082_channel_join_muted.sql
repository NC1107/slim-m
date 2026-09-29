-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Per-channel "join muted" default: a voice channel with this set asks every
-- client to open the mic off on join. A default, not a lock: members can
-- unmute themselves, and SPEAK overwrites are what actually restrict who may
-- speak. 0 (the default, and what every existing channel keeps) means off.
ALTER TABLE channels ADD COLUMN join_muted INTEGER NOT NULL DEFAULT 0
    CHECK (join_muted IN (0, 1));
