-- SPDX-License-Identifier: AGPL-3.0-only
-- Whether a member wants a message preview sealed into their push envelopes,
-- as an account choice rather than a per-device one: a reinstall or a new
-- sign-in makes a fresh device row, and the per-device flag it started with
-- (0) silently turned previews off for everyone who never re-toggled it.
--
-- NULL means the member never chose, and the server applies
-- `DEFAULT_PUSH_PREVIEW` (src/notifications.rs). Existing accounts keep what
-- their devices already said: 1 if any device opted in, else NULL.
ALTER TABLE users ADD COLUMN push_include_content INTEGER;

UPDATE users SET push_include_content = 1
WHERE EXISTS (
    SELECT 1 FROM devices
    WHERE devices.user_id = users.id AND devices.push_include_content = 1
);
