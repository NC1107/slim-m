-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- A deployment-wide ceiling on screen-share resolution, so an admin can bound
-- the load a screen share puts on every client and the SFU. Client-advertised:
-- the client reads this and caps its own capture/publish parameters before
-- starting a share; there is no server-side track inspection.
--
-- 2160 (the highest resolution ScreenShareQuality.crisp already asks a
-- desktop to publish - see client/packages/rtc/lib/src/screen_share.dart) is
-- the default and what every deployment that predates this setting keeps on
-- upgrade, so behaviour is unchanged until an admin lowers it. Only the lower
-- bound is a CHECK; the settable range is enforced in Rust in
-- set_screen_share_max_height, the same split message_retention_days and
-- canvas_object_cap use: the DB guards the invariant, Rust guards the policy.
ALTER TABLE space_settings ADD COLUMN screen_share_max_height INTEGER NOT NULL DEFAULT 2160
    CHECK (screen_share_max_height >= 1);
