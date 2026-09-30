-- SPDX-License-Identifier: AGPL-3.0-only
-- A report about a bot's private (ephemeral) message names no stored message,
-- so the bot that wrote it is recorded on the report itself. Null for every
-- other report, whose author is joined from `messages` at read time.
ALTER TABLE reports
    ADD COLUMN snapshot_author_id BLOB REFERENCES users(id) ON DELETE SET NULL;

CREATE INDEX reports_snapshot_author
    ON reports(snapshot_author_id) WHERE snapshot_author_id IS NOT NULL;
