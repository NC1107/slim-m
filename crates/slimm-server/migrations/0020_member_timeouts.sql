-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- A timeout: a member keeps reading and loses every way of expressing
-- themselves, for a while, without anybody deleting anything.
--
-- The moderation tools until now were all-or-nothing at opposite ends -
-- delete one message, or delete the whole account - so the ordinary case of
-- "stop, go and cool off" had no answer that was not permanent. Discord calls
-- this a timeout and that is the word people arrive already knowing.
--
-- One row per member rather than a history: this table answers "is this
-- person timed out right now", and a second concurrent timeout on one member
-- is not a thing that means anything. Re-timing-out somebody replaces the
-- row, which is also how a moderator shortens one.
--
-- `until` is Unix milliseconds like every other timestamp here, and an
-- elapsed row is left in place rather than swept: it is at most one row per
-- member, every read already compares against the clock, and keeping it means
-- a moderator can still see that a timeout was the last thing that happened.
CREATE TABLE member_timeouts (
    user_id   BLOB PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    until     INTEGER NOT NULL,
    reason    TEXT,
    -- Null once the moderator's own account is deleted; the timeout outlives
    -- whoever issued it, since lifting it early is somebody else's call too.
    issued_by BLOB REFERENCES users(id) ON DELETE SET NULL,
    issued_at INTEGER NOT NULL
) STRICT;
