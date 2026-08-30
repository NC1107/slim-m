-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- A per-(user, channel) override of the account-wide notification
-- preference (users.notification_preference, migration 0032): mute one
-- channel, or narrow it to mentions only, while every other channel keeps
-- following the account default.
--
-- Absence of a row here means "use the account default" - the same
-- resolve-through-the-parent-if-absent shape read_states and
-- channel_overwrites already use, rather than a second copy of the default
-- written everywhere up front. Only 'mentions' and 'nothing' are ever
-- written (validated in the application layer,
-- http/channel_notification_prefs.rs): 'everything' is what having no row
-- already means, so writing it would be a second spelling of the same
-- answer rather than a real override.
CREATE TABLE channel_notification_prefs (
    user_id    BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    channel_id BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    preference TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, channel_id)
) STRICT, WITHOUT ROWID;

-- Push fan-out resolves this per channel across many users at once, the
-- opposite direction from the primary key's own (user_id, channel_id) lead;
-- without this a channel-scoped lookup falls back to a full table scan.
CREATE INDEX channel_notification_prefs_channel ON channel_notification_prefs(channel_id);
