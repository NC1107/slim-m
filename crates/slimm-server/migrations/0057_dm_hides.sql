-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Closing a DM out of the sidebar: a per-viewer hide, never a delete. The
-- other participant's own list is untouched, and no message is removed -
-- `store/dms.rs`'s `list_dm_conversations` simply stops listing this channel
-- for this one viewer until it has something new to show them.
--
-- `hidden_at` is compared against that query's own `activity_at`, not
-- cleared by an incoming message: a hidden DM must come back on its own once
-- the other person writes again, and re-deriving "is this still hidden" from
-- two timestamps at read time costs nothing extra there, while clearing the
-- row on every incoming message would be a write on every message sent into
-- every DM in the deployment just to cover the rare one that is hidden.
--
-- The other way back - the viewer reopening or re-messaging the same person
-- - is handled in `Store::open_dm`, which deletes this row for the caller
-- whenever it finds (or creates) their channel with that pair: hiding is
-- reversible by the same action that would naturally follow.
--
-- One row per (user, channel), keyed like `channel_notification_prefs`
-- (0045_channel_notification_prefs.sql): the caller's own preference about a
-- channel, gone with their account and independent of everything else that
-- can be true of the same channel - muted or not, blocked or not.
CREATE TABLE dm_hides (
    user_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    channel_id BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    hidden_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, channel_id)
) STRICT, WITHOUT ROWID;
