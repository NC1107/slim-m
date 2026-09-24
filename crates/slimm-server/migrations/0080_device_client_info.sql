-- SPDX-License-Identifier: AGPL-3.0-only
-- What signed this device in: a coarse client kind ("ios", "android",
-- "desktop", "web") and the app version, so the devices list can name a
-- session by more than the free-text device name a client happens to pick.
-- Both NULL on a session opened before this shipped, which the client reads
-- as "unknown" and falls back to the plain device name for, the same
-- "absent means older server/client" convention every field added to an
-- existing row here follows.
ALTER TABLE devices ADD COLUMN client_kind TEXT;
ALTER TABLE devices ADD COLUMN client_version TEXT;
