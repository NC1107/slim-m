-- SPDX-License-Identifier: AGPL-3.0-only
--
-- What happened to a DM call, so a call that was never answered leaves a
-- trace. Until now every part of ringing was ephemeral: the ring lives in
-- memory, the sweep tears it down after the timeout, and nothing was written
-- anywhere - so a missed call was invisible to the person who missed it.
--
-- Carried by a message rather than kept in a log of its own. A call is an
-- event in a conversation, and the transcript is where a person looks for
-- what happened in one; riding a message also means this inherits ordering,
-- pagination, sync, unread state and notification without any of them
-- learning a new kind of thing. That is the same choice polls, forwards and
-- app surfaces made, and `http/message_enrich.rs` already has the one shared
-- place a page of messages gets its extras attached.
--
-- Keyed by message_id for the same reason app_surfaces is: a call record
-- never outlives or moves between messages.
--
-- outcome is the text form of `voice::CallRingOutcome` - answered, declined,
-- canceled, timed_out - checked here rather than left to the writer, since a
-- row with an outcome nothing renders would be a silently blank call in a
-- transcript.
--
-- duration_ms is null for every outcome but answered: there is no call to
-- have lasted anything when nobody picked up.
--
-- Messages are soft-deleted (deleted_at set; the row never actually goes
-- away), so an ON DELETE CASCADE from messages alone would never fire. The
-- trigger below fires the moment deleted_at is first set, exactly like polls'
-- and app surfaces' own cleanup triggers.
CREATE TABLE call_records (
    message_id  BLOB PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
    channel_id  BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    caller_id   BLOB REFERENCES users(id) ON DELETE SET NULL,
    outcome     TEXT NOT NULL CHECK (
        outcome IN ('answered', 'declined', 'canceled', 'timed_out')
    ),
    duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
    created_at  INTEGER NOT NULL
) STRICT;

CREATE INDEX call_records_channel ON call_records(channel_id);

CREATE TRIGGER call_records_on_message_delete
AFTER UPDATE OF deleted_at ON messages
WHEN NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL
BEGIN
    DELETE FROM call_records WHERE message_id = NEW.id;
END;
