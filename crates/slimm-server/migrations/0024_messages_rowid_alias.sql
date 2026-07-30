-- SPDX-License-Identifier: AGPL-3.0-only
-- An explicit rowid alias on `messages`, so the full-text index is keyed on a
-- column SQLite promises to keep.
--
-- `messages_fts` is an external-content FTS5 table declared with
-- content='messages', content_rowid='rowid' (0002). `messages` is STRICT with
-- PRIMARY KEY (channel_id, seq) and no INTEGER PRIMARY KEY, so its rowid is
-- implicit - and SQLite documents VACUUM as free to renumber the rowids of any
-- table without an INTEGER PRIMARY KEY. The fts5 shadow tables are carried
-- across unchanged, so every index entry would come to point at a different
-- message: search answering with the wrong rows, silently, with no error
-- anywhere and `PRAGMA integrity_check` clean. `VACUUM INTO` is how the backup
-- copy is taken, so the first place it lands is a backup nobody reads until a
-- restore. 0015_canvas_rtree.sql refused exactly this licence for the R-Tree
-- and gave `canvas_objects` an `rt_id INTEGER PRIMARY KEY`; this is the same
-- withdrawal, on the older and much larger table.
--
-- `fts_rowid INTEGER PRIMARY KEY` is an alias for the rowid, which withdraws
-- the licence at no storage or query cost. Naming it in `content_rowid` is the
-- other half: the coupling between the index and the column it is keyed on
-- becomes greppable from both ends rather than resting on an implicit thing a
-- reader has to already know about.
--
-- STRICT tables cannot gain an INTEGER PRIMARY KEY by ALTER TABLE, so this is
-- a table rebuild against live data, unattended, on a deployment that
-- auto-updates. Four choices shape it, and each is load-bearing:
--
-- 1. One sqlx transaction, foreign keys ON throughout. sqlx wraps a migration
--    script and its own bookkeeping row in a single transaction, so a failure
--    at any point - a CHECK, a foreign key, a full disk, a SIGKILL - leaves
--    the database byte for byte what it was, with no _sqlx_migrations row and
--    so a clean retry on the next boot. That rules out the textbook 12-step
--    procedure, which needs `PRAGMA foreign_keys = OFF` and therefore a COMMIT
--    mid-script: the window it opens is a half-rebuilt schema no restart can
--    reason about, and that is the outcome worth designing away from here.
-- 2. Nothing is renamed. ALTER TABLE ... RENAME rewrites every REFERENCES
--    clause and trigger body naming the table while leaving the fts5
--    content='messages' argument alone, so the rebuild would have to undo the
--    fixup it just caused. Dropping and recreating under the final name leaves
--    the four child REFERENCES clauses untouched and rebinding by name.
-- 3. The six cascade-reachable children are copied aside, emptied explicitly
--    child-before-parent, and restored after. Emptying first is not tidiness:
--    pinned_messages has no index led by message_id, so the implicit cascade
--    from DROP TABLE scans the whole pin table once per message deleted, which
--    is O(messages x pins) inside the transaction: measured at 200,000
--    messages and 20,000 pins, the version relying on the cascade had not
--    finished after eight minutes, while six whole-table DELETEs cost nothing
--    measurable. The restores then run under live foreign key enforcement,
--    parent before child, so a child can never be restored against a parent
--    that is not there.
-- 4. Every step is asserted by a CHECK-constrained guard table. SQL has no
--    assertion, so each invariant is inserted as a value that must be zero and
--    a discrepancy becomes a named constraint error, which aborts the script
--    and rolls the whole migration back. The guards are the difference between
--    this being a migration and being a hope. The first of them runs before
--    anything destructive: a database that already violates one of these
--    foreign keys (reachable through a restore, or hand-written SQL under the
--    sqlite3 CLI, which defaults foreign_keys OFF) cannot be rebuilt, because
--    the restore re-checks what the old table only checked at write time.
--
-- The statements below carry one-line comments, so the reasoning behind the
-- ones that are easy to get wrong is here instead:
--
-- * `PRIMARY KEY (channel_id, seq)` becomes `UNIQUE` because a table has one
--   primary key. Both columns were already explicitly NOT NULL and the index
--   behind them is the same index in the same order, so no read plan changes -
--   only the `origin` flag on `sqlite_autoindex_messages_2`, which nothing
--   reads. It does mean a future foreign key written as a bare `REFERENCES
--   messages` binds to `fts_rowid` rather than erroring; spell the column, as
--   all four existing children do.
-- * The existing rowid values are carried across rather than renumbered, so
--   this is a pure schema tightening: nothing that ever read a rowid sees a
--   different one, and the index is still repopulated from scratch, because
--   nothing has ever verified that the live one is right.
-- * `content_rowid` is fixed at creation, so naming the new column needs the
--   virtual table recreated; its four shadow tables go with it, come back
--   empty, and are refilled below.
-- * The three FTS triggers are 0007's guarded forms, not 0002's. 0002's delete
--   and update triggers issue their 'delete' unconditionally, which corrupts
--   an external-content index once an unindexed row exists, and that is the
--   bug 0007 exists to have fixed.
-- * `pinned_messages_on_delete` and `polls_on_message_delete` are not FTS but
--   are dropped by the same DROP TABLE. Without them a soft-deleted message
--   keeps its pin and its poll, which the UI renders as a blank.
-- * The index is repopulated by a SELECT mirroring `messages_fts_ai`'s
--   `is_encrypted` guard, deliberately not by fts5's own 'rebuild' command,
--   which scans the content table with no WHERE clause and would index the
--   encrypted rows the triggers exclude. There is no `deleted_at` filter
--   either: the triggers have none, and an index missing a soft-deleted row
--   corrupts on that row's next edit, when `messages_fts_au` issues a 'delete'
--   for a rowid the index never held.
-- * Each child guard is the row-count difference plus the number of saved rows
--   that did not come back byte for byte, with abs() on the first so a loss and
--   a gain cannot cancel. EXCEPT compares every column and treats NULLs as
--   equal. The FTS guard counts `messages_fts_docsize`, the shadow table with
--   one row per indexed document, because counting `messages_fts` itself would
--   prove nothing: a scan of an external-content table reads the content table,
--   so it would compare `messages` with itself.
-- * Only the rank-1 `integrity-check` checksums the index against the content
--   table, and it cannot be filtered, so it is written to perform no insert at
--   all on a database holding an encrypted row rather than raise a false alarm
--   there. None can exist today, so it does run; the day E2EE lands it stops,
--   and the counting guards are what remain.
--
-- This file must never be run by hand: the sqlite3 CLI does not stop on error
-- unless `.bail on` is set, so a guard failure there would be stepped straight
-- over and the cleanup committed on top of it.
--
-- Cost, measured on 200,000 messages, 10,000 reactions and 20,000 pins in a
-- 52 MB database: 1.9 seconds. The whole rebuild sits in the WAL until commit,
-- peaking at 72 MB there, so the volume needs room for about 2.4x the database
-- while it runs; afterwards the main file keeps the freed pages and stays
-- around 40% larger until an operator VACUUMs, which this cannot do for them
-- because VACUUM refuses to run inside a transaction.

DROP TABLE IF EXISTS messages_rebuild_guard_orphans;
DROP TABLE IF EXISTS messages_rebuild_guard_messages;
DROP TABLE IF EXISTS messages_rebuild_guard_children;
DROP TABLE IF EXISTS messages_rebuild_guard_index;
DROP TABLE IF EXISTS messages_rebuild_rows;
DROP TABLE IF EXISTS messages_rebuild_reactions;
DROP TABLE IF EXISTS messages_rebuild_attachments;
DROP TABLE IF EXISTS messages_rebuild_pins;
DROP TABLE IF EXISTS messages_rebuild_polls;
DROP TABLE IF EXISTS messages_rebuild_poll_options;
DROP TABLE IF EXISTS messages_rebuild_poll_votes;

CREATE TABLE messages_rebuild_guard_orphans (
    orphans INTEGER NOT NULL
        CONSTRAINT preexisting_foreign_key_orphans CHECK (orphans = 0)
) STRICT;

INSERT INTO messages_rebuild_guard_orphans (orphans) SELECT
    (SELECT count(*) FROM pragma_foreign_key_check('messages'))
  + (SELECT count(*) FROM pragma_foreign_key_check('reactions'))
  + (SELECT count(*) FROM pragma_foreign_key_check('message_attachments'))
  + (SELECT count(*) FROM pragma_foreign_key_check('pinned_messages'))
  + (SELECT count(*) FROM pragma_foreign_key_check('polls'))
  + (SELECT count(*) FROM pragma_foreign_key_check('poll_options'))
  + (SELECT count(*) FROM pragma_foreign_key_check('poll_votes'));

-- The one moment the existing rowid values are still readable.
CREATE TABLE messages_rebuild_rows AS
    SELECT rowid AS fts_rowid, id, channel_id, author_id, seq, content,
           is_encrypted, created_at, edited_at, deleted_at
    FROM messages;
CREATE TABLE messages_rebuild_reactions AS
    SELECT message_id, user_id, emoji, created_at FROM reactions;
CREATE TABLE messages_rebuild_attachments AS
    SELECT message_id, sha256, position FROM message_attachments;
CREATE TABLE messages_rebuild_pins AS
    SELECT channel_id, message_id, pinned_by, pinned_at FROM pinned_messages;
CREATE TABLE messages_rebuild_polls AS
    SELECT message_id, channel_id, question, close_at, created_by, created_at
    FROM polls;
CREATE TABLE messages_rebuild_poll_options AS
    SELECT message_id, position, label FROM poll_options;
CREATE TABLE messages_rebuild_poll_votes AS
    SELECT message_id, user_id, position, voted_at FROM poll_votes;

DELETE FROM poll_votes;
DELETE FROM poll_options;
DELETE FROM polls;
DELETE FROM pinned_messages;
DELETE FROM message_attachments;
DELETE FROM reactions;

DROP TABLE messages;

-- (channel_id, seq) becomes UNIQUE because a table has one primary key.
CREATE TABLE messages (
    fts_rowid    INTEGER PRIMARY KEY,     -- rowid alias; keys messages_fts
    id           BLOB NOT NULL UNIQUE,    -- UUIDv7 identity
    channel_id   BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    author_id    BLOB REFERENCES users(id) ON DELETE SET NULL,
    seq          INTEGER NOT NULL,
    content      TEXT NOT NULL DEFAULT '',
    is_encrypted INTEGER NOT NULL DEFAULT 0,
    created_at   INTEGER NOT NULL,
    edited_at    INTEGER,
    deleted_at   INTEGER,
    UNIQUE (channel_id, seq)
) STRICT;

-- The existing rowid values are carried across, never renumbered.
INSERT INTO messages (fts_rowid, id, channel_id, author_id, seq, content,
                      is_encrypted, created_at, edited_at, deleted_at)
    SELECT fts_rowid, id, channel_id, author_id, seq, content,
           is_encrypted, created_at, edited_at, deleted_at
    FROM messages_rebuild_rows;

CREATE INDEX messages_channel_live
    ON messages(channel_id, seq DESC) WHERE deleted_at IS NULL;
CREATE INDEX messages_author
    ON messages(author_id) WHERE author_id IS NOT NULL;

INSERT INTO reactions (message_id, user_id, emoji, created_at)
    SELECT message_id, user_id, emoji, created_at
    FROM messages_rebuild_reactions;
INSERT INTO message_attachments (message_id, sha256, position)
    SELECT message_id, sha256, position FROM messages_rebuild_attachments;
INSERT INTO pinned_messages (channel_id, message_id, pinned_by, pinned_at)
    SELECT channel_id, message_id, pinned_by, pinned_at
    FROM messages_rebuild_pins;
INSERT INTO polls (message_id, channel_id, question, close_at, created_by, created_at)
    SELECT message_id, channel_id, question, close_at, created_by, created_at
    FROM messages_rebuild_polls;
INSERT INTO poll_options (message_id, position, label)
    SELECT message_id, position, label FROM messages_rebuild_poll_options;
INSERT INTO poll_votes (message_id, user_id, position, voted_at)
    SELECT message_id, user_id, position, voted_at
    FROM messages_rebuild_poll_votes;

-- content_rowid is fixed at creation, so the alias needs a new virtual table.
DROP TABLE messages_fts;

CREATE VIRTUAL TABLE messages_fts USING fts5(
    content,
    content='messages',
    content_rowid='fts_rowid',
    tokenize='unicode61'
);

CREATE TRIGGER messages_fts_ai AFTER INSERT ON messages WHEN NEW.is_encrypted = 0 BEGIN
    INSERT INTO messages_fts(rowid, content) VALUES (NEW.fts_rowid, NEW.content);
END;

-- 0007's guarded forms, not 0002's: only ever delete what was indexed.
CREATE TRIGGER messages_fts_ad AFTER DELETE ON messages WHEN OLD.is_encrypted = 0 BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content)
        VALUES ('delete', OLD.fts_rowid, OLD.content);
END;

CREATE TRIGGER messages_fts_au AFTER UPDATE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content)
        SELECT 'delete', OLD.fts_rowid, OLD.content WHERE OLD.is_encrypted = 0;
    INSERT INTO messages_fts(rowid, content)
        SELECT NEW.fts_rowid, NEW.content WHERE NEW.is_encrypted = 0;
END;

-- Not FTS, but dropped by the same DROP TABLE and just as easy to forget.
CREATE TRIGGER pinned_messages_on_delete
AFTER UPDATE OF deleted_at ON messages
WHEN NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL
BEGIN
    DELETE FROM pinned_messages WHERE message_id = NEW.id;
END;

CREATE TRIGGER polls_on_message_delete
AFTER UPDATE OF deleted_at ON messages
WHEN NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL
BEGIN
    DELETE FROM polls WHERE message_id = NEW.id;
END;

-- Mirrors messages_fts_ai's guard, and deliberately not fts5's own 'rebuild'.
INSERT INTO messages_fts(rowid, content)
    SELECT fts_rowid, content FROM messages WHERE is_encrypted = 0;

CREATE TABLE messages_rebuild_guard_messages (
    rows    INTEGER NOT NULL CONSTRAINT messages_row_count_changed CHECK (rows = 0),
    content INTEGER NOT NULL CONSTRAINT messages_content_changed CHECK (content = 0)
) STRICT;

INSERT INTO messages_rebuild_guard_messages (rows, content) VALUES (
    (SELECT count(*) FROM messages) - (SELECT count(*) FROM messages_rebuild_rows),
    (SELECT count(*) FROM (
        SELECT fts_rowid, id, channel_id, author_id, seq, content,
               is_encrypted, created_at, edited_at, deleted_at
        FROM messages_rebuild_rows
        EXCEPT
        SELECT fts_rowid, id, channel_id, author_id, seq, content,
               is_encrypted, created_at, edited_at, deleted_at
        FROM messages))
);

-- Row-count difference plus saved rows that did not come back byte for byte.
CREATE TABLE messages_rebuild_guard_children (
    reactions   INTEGER NOT NULL CONSTRAINT reactions_differ CHECK (reactions = 0),
    attachments INTEGER NOT NULL CONSTRAINT message_attachments_differ CHECK (attachments = 0),
    pins        INTEGER NOT NULL CONSTRAINT pinned_messages_differ CHECK (pins = 0),
    polls       INTEGER NOT NULL CONSTRAINT polls_differ CHECK (polls = 0),
    options     INTEGER NOT NULL CONSTRAINT poll_options_differ CHECK (options = 0),
    votes       INTEGER NOT NULL CONSTRAINT poll_votes_differ CHECK (votes = 0)
) STRICT;

INSERT INTO messages_rebuild_guard_children
    (reactions, attachments, pins, polls, options, votes)
VALUES (
    abs((SELECT count(*) FROM reactions)
        - (SELECT count(*) FROM messages_rebuild_reactions))
      + (SELECT count(*) FROM (SELECT * FROM messages_rebuild_reactions
            EXCEPT SELECT message_id, user_id, emoji, created_at FROM reactions)),
    abs((SELECT count(*) FROM message_attachments)
        - (SELECT count(*) FROM messages_rebuild_attachments))
      + (SELECT count(*) FROM (SELECT * FROM messages_rebuild_attachments
            EXCEPT SELECT message_id, sha256, position FROM message_attachments)),
    abs((SELECT count(*) FROM pinned_messages)
        - (SELECT count(*) FROM messages_rebuild_pins))
      + (SELECT count(*) FROM (SELECT * FROM messages_rebuild_pins
            EXCEPT SELECT channel_id, message_id, pinned_by, pinned_at FROM pinned_messages)),
    abs((SELECT count(*) FROM polls)
        - (SELECT count(*) FROM messages_rebuild_polls))
      + (SELECT count(*) FROM (SELECT * FROM messages_rebuild_polls
            EXCEPT SELECT message_id, channel_id, question, close_at, created_by, created_at FROM polls)),
    abs((SELECT count(*) FROM poll_options)
        - (SELECT count(*) FROM messages_rebuild_poll_options))
      + (SELECT count(*) FROM (SELECT * FROM messages_rebuild_poll_options
            EXCEPT SELECT message_id, position, label FROM poll_options)),
    abs((SELECT count(*) FROM poll_votes)
        - (SELECT count(*) FROM messages_rebuild_poll_votes))
      + (SELECT count(*) FROM (SELECT * FROM messages_rebuild_poll_votes
            EXCEPT SELECT message_id, user_id, position, voted_at FROM poll_votes))
);

-- Everything a hand-retyped trigger or index gets wrong and commits clean on.
CREATE TABLE messages_rebuild_guard_index (
    documents INTEGER NOT NULL CONSTRAINT fts_document_count_wrong CHECK (documents = 0),
    triggers  INTEGER NOT NULL CONSTRAINT messages_triggers_missing CHECK (triggers = 5),
    indexes   INTEGER NOT NULL CONSTRAINT messages_indexes_missing CHECK (indexes = 2),
    alias     INTEGER NOT NULL CONSTRAINT messages_rowid_alias_missing CHECK (alias = 1),
    keyed_on  INTEGER NOT NULL CONSTRAINT fts_content_rowid_wrong CHECK (keyed_on = 1)
) STRICT;

INSERT INTO messages_rebuild_guard_index
    (documents, triggers, indexes, alias, keyed_on)
VALUES (
    (SELECT count(*) FROM messages_fts_docsize)
        - (SELECT count(*) FROM messages WHERE is_encrypted = 0),
    (SELECT count(*) FROM sqlite_master
        WHERE type = 'trigger' AND tbl_name = 'messages'),
    (SELECT count(*) FROM sqlite_master
        WHERE type = 'index' AND tbl_name = 'messages'
          AND name IN ('messages_channel_live', 'messages_author')),
    (SELECT count(*) FROM pragma_table_info('messages')
        WHERE name = 'fts_rowid' AND type = 'INTEGER' AND pk = 1),
    (SELECT count(*) FROM sqlite_master
        WHERE name = 'messages_fts' AND instr(sql, 'content_rowid=''fts_rowid''') > 0)
);

-- The bare form checks structure; only the rank-1 form checks the content.
INSERT INTO messages_fts(messages_fts) VALUES('integrity-check');
INSERT INTO messages_fts(messages_fts, rank)
    SELECT 'integrity-check', 1
    WHERE NOT EXISTS (SELECT 1 FROM messages WHERE is_encrypted <> 0);

DROP TABLE messages_rebuild_guard_orphans;
DROP TABLE messages_rebuild_guard_messages;
DROP TABLE messages_rebuild_guard_children;
DROP TABLE messages_rebuild_guard_index;
DROP TABLE messages_rebuild_rows;
DROP TABLE messages_rebuild_reactions;
DROP TABLE messages_rebuild_attachments;
DROP TABLE messages_rebuild_pins;
DROP TABLE messages_rebuild_polls;
DROP TABLE messages_rebuild_poll_options;
DROP TABLE messages_rebuild_poll_votes;
