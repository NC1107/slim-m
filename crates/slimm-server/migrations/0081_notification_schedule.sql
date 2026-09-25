-- SPDX-License-Identifier: AGPL-3.0-only
-- The notification schedule (docs/decisions/0033-notification-schedule.md):
-- replaces the single UTC-minutes quiet-hours window (migration 0056,
-- `users.quiet_hours_*`) with a per-weekday schedule evaluated in the
-- account's own IANA time zone, an off-hours policy, and two allow-lists.
-- The old columns and the `/push/quiet-hours` routes are left exactly as
-- they are - only push enforcement (`push::recipients`) moves to this model.
--
-- One row per account. off_hours_mode is 'mentions' (today's quiet-hours
-- behaviour, and the default so nobody's push changes on upgrade) or
-- 'nothing'. snooze_until is an epoch-millisecond deadline, NULL when not
-- snoozing.
CREATE TABLE notification_schedules (
    user_id BLOB PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    timezone TEXT NOT NULL,
    off_hours_mode TEXT NOT NULL DEFAULT 'mentions',
    snooze_until INTEGER,
    updated_at INTEGER NOT NULL
) STRICT, WITHOUT ROWID;

-- One optional on-hours window per weekday (0 = Monday .. 6 = Sunday, jiff's
-- own Monday-zero numbering, so the wire, this table and jiff never need a
-- translation table). A weekday absent here has no on-hours window at all -
-- the whole day is off hours. end_minute may be less than start_minute for a
-- window that starts this weekday and crosses midnight into the next one
-- (Friday 22:00 into Saturday 02:00 is the motivating case): the early
-- morning tail is read against the following weekday's own evaluation, never
-- stored a second time.
CREATE TABLE notification_schedule_days (
    user_id BLOB NOT NULL REFERENCES notification_schedules(user_id) ON DELETE CASCADE,
    weekday INTEGER NOT NULL CHECK (weekday >= 0 AND weekday <= 6),
    start_minute INTEGER NOT NULL CHECK (start_minute >= 0 AND start_minute < 1440),
    end_minute INTEGER NOT NULL CHECK (end_minute >= 0 AND end_minute < 1440 AND end_minute != start_minute),
    PRIMARY KEY (user_id, weekday)
) STRICT, WITHOUT ROWID;

-- The off-hours "notify me about this person" allow-list: a DM or mention
-- from allowed_user_id still notifies during off hours even in 'nothing'
-- mode, floored at mentions-shaped, never raised to 'everything' - see
-- notification_schedule::degrade_for_off_hours for why.
--
-- References users(id) directly, not notification_schedules(user_id): the
-- member card's "notify me about this person off-hours" shortcut can add an
-- entry before the account has ever set up a schedule at all (it is inert
-- until they do, the same as any allow-list with nothing to override).
CREATE TABLE notification_schedule_allowed_users (
    user_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    allowed_user_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, allowed_user_id)
) STRICT, WITHOUT ROWID;

-- The off-hours channel allow-list: allowed_channel_id notifies exactly as
-- it would in hours (the account's ordinary preference for that channel),
-- bypassing off-hours narrowing entirely rather than floored at mentions.
-- Also independent of notification_schedules(user_id); see above.
CREATE TABLE notification_schedule_allowed_channels (
    user_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    allowed_channel_id BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, allowed_channel_id)
) STRICT, WITHOUT ROWID;

-- Both allow-lists are looked up by their target, not their owner, on the
-- push path (`push::recipients` asks "which of these viewers allow-list this
-- author/channel", not "what does this one viewer allow-list").
CREATE INDEX notification_schedule_allowed_users_target ON notification_schedule_allowed_users(allowed_user_id);
CREATE INDEX notification_schedule_allowed_channels_target ON notification_schedule_allowed_channels(allowed_channel_id);

-- Migrate existing quiet-hours users so nobody's push changes on upgrade.
-- The stored minutes are already UTC clock minutes, so a schedule with
-- timezone 'UTC' reproduces the exact same absolute window every day - not
-- an approximation. The window itself is inverted (end, start rather than
-- start, end): quiet_hours_* named the window to go *quiet* in, and this
-- table names the window to stay *on* in, and the complement of a circular
-- [start, end) window is exactly [end, start) - see
-- docs/decisions/0033-notification-schedule.md for the worked example.
INSERT INTO notification_schedules (user_id, timezone, off_hours_mode, snooze_until, updated_at)
SELECT id, 'UTC', 'mentions', NULL, unixepoch() * 1000
FROM users
WHERE quiet_hours_start_minute IS NOT NULL AND quiet_hours_end_minute IS NOT NULL;

INSERT INTO notification_schedule_days (user_id, weekday, start_minute, end_minute)
SELECT u.id, w.weekday, u.quiet_hours_end_minute, u.quiet_hours_start_minute
FROM users u
CROSS JOIN (
    SELECT 0 AS weekday UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL
    SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6
) w
WHERE u.quiet_hours_start_minute IS NOT NULL AND u.quiet_hours_end_minute IS NOT NULL;
