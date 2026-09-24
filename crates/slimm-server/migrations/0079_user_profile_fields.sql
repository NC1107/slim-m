-- SPDX-License-Identifier: AGPL-3.0-only
-- Profile-first fields for the member card and Settings > Profile: pronouns,
-- a short about line, and a profile colour. NULL means "not set", the same
-- optional-column convention `status_text` (migration 0046) uses.
--
-- profile_color is an index into the design system's closed categorical set
-- (`AppCanvasColors.cursors`, six hues) rather than a raw colour, so a stored
-- value keeps meaning a fixed hue in both themes instead of an RGB triple
-- that could land illegibly on either background. Bounds are enforced in the
-- application layer, the same convention every free-text length cap here
-- uses rather than a CHECK constraint.
ALTER TABLE users ADD COLUMN pronouns TEXT;
ALTER TABLE users ADD COLUMN about TEXT;
ALTER TABLE users ADD COLUMN profile_color INTEGER;
