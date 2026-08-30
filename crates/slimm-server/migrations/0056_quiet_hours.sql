-- SPDX-License-Identifier: AGPL-3.0-only
-- Quiet hours: an optional per-account time-of-day window, stored in
-- minutes since midnight UTC (0-1439), during which an `everything`
-- notification preference is narrowed to `mentions` by
-- `push::recipients::narrow_for_notification_preference` - never to
-- `nothing`, and never touching an account whose preference is already
-- `mentions` or `nothing`. Entered in local time in the settings UI and
-- converted to UTC before it ever reaches this column, so the server never
-- needs to know the account's time zone to evaluate it.
--
-- NULL means disabled, the default, and what every account that predates
-- this feature keeps on upgrade. Both columns are NULL or both are set:
-- there is no such thing as a start with no end. `quiet_hours_end_minute`
-- may be less than `quiet_hours_start_minute` for a window that crosses
-- midnight (23:00-08:00 is the ordinary case, not an edge case), so
-- `notifications::QuietHours::contains` reads the pair as a clock face
-- rather than assuming `start <= now <= end`.
--
-- Range and pairing are enforced in the application layer for the same
-- reason `status_text` (migration 0046) leaves length unchecked in SQL:
-- this is validated in `http/quiet_hours.rs` before it ever reaches
-- `set_quiet_hours`, and the CHECK below is a backstop, not the primary
-- guard.
ALTER TABLE users ADD COLUMN quiet_hours_start_minute INTEGER
    CHECK (quiet_hours_start_minute IS NULL OR (quiet_hours_start_minute >= 0 AND quiet_hours_start_minute < 1440));
ALTER TABLE users ADD COLUMN quiet_hours_end_minute INTEGER
    CHECK (quiet_hours_end_minute IS NULL OR (quiet_hours_end_minute >= 0 AND quiet_hours_end_minute < 1440));
