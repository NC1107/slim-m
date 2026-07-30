-- user_blocks is keyed (blocker_id, blocked_id) WITHOUT ROWID, which answers
-- "who has this member blocked" from the primary key and "who has blocked this
-- member" by scanning the whole table.
--
-- Only the first direction had a caller until push fan-out grew the second, and
-- that one runs on the message write path, once per message, so a table scan
-- there is paid by every send in the deployment rather than by the settings
-- screen. The index is the reverse prefix.
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON user_blocks (blocked_id);
