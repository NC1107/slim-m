-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Push notification support.
--
-- 0002 already carries push_token_ref, voip_push_token_ref, and
-- push_public_key on devices. Missing for push to actually trigger correctly:
--
--   platform                the device's push platform, 'ios' | 'android',
--                           set together with the token at registration.
--   lifecycle_state         the client's last self-reported app lifecycle
--                           state (for example 'foreground' | 'background').
--   lifecycle_reported_at   when that state was reported, unix milliseconds.
--
-- Triggering push from raw WebSocket presence does not work: iOS suspends a
-- socket without closing it, so a live connection is not proof the app can
-- show a notification. Triggering instead reads the client-reported lifecycle
-- state, and its timestamp lets a stale report be told apart from a current one.

ALTER TABLE devices ADD COLUMN platform TEXT;
ALTER TABLE devices ADD COLUMN lifecycle_state TEXT;
ALTER TABLE devices ADD COLUMN lifecycle_reported_at INTEGER;
