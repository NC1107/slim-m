-- SPDX-License-Identifier: AGPL-3.0-only
-- The Voice Canvas spatial index, plus the two changes to `canvas_objects`
-- that make it safe to keep.
--
-- 0002 created `canvas_objects` and `canvas_ops` and left a note saying the
-- R-Tree arrives with the canvas build. Nothing has ever written a canvas row:
-- no route, no store method, no trigger, only the account-anonymization UPDATE
-- in `store/sessions.rs`, which matches zero rows on every deployment that
-- exists. That is why this recreates the table outright rather than ALTERing
-- it. There is no data anywhere to migrate, and neither change below can be
-- made by ALTER TABLE on a STRICT table at all.
--
-- Change one: an explicit `rt_id INTEGER PRIMARY KEY`.
--
-- An R-Tree is keyed by one integer. `canvas_objects` is keyed by
-- (channel_id, seq), and its identity column is a 16-byte UUIDv7 BLOB, so
-- something has to bridge the two. The obvious bridge is the implicit rowid
-- the table already has, since 0002 deliberately left it a rowid table. The
-- reason not to use it is that SQLite does not promise to keep it: VACUUM is
-- documented as free to renumber the rowids of any table with no INTEGER
-- PRIMARY KEY, and the R-Tree's shadow tables would be carried across
-- unchanged, so every entry would come to point at a different object. Nothing
-- would report it, and the first place it lands is the `VACUUM INTO` hot copy
-- the backup story is built on: a wrong index in a backup nobody reads until a
-- restore. SQLite 3.46 happens to preserve them (checked, on this schema, with
-- 20,000 rows through both VACUUM and VACUUM INTO), which makes this a licence
-- the implementation has not taken rather than a bug being fixed - and a
-- licence is not something to build an index on. An explicit INTEGER PRIMARY
-- KEY is an alias for the rowid and withdraws the licence, at no cost.
--
-- Change two: `channel_key`, carried as the R-Tree's third dimension.
--
-- One R-Tree serves the whole deployment. Without a channel dimension, a
-- viewport read in one channel walks every other channel's canvas as well,
-- because every canvas starts at the same origin and they all overlap. The
-- key is a 24-bit discriminant of the channel id: 24 bits because R-Tree
-- coordinates are 32-bit floats, which hold integers below 2^24 exactly.
-- Collisions cost pruning only, never correctness - `o.channel_id = ?` is
-- still compared exactly in every query.
DROP TABLE canvas_objects;

CREATE TABLE canvas_objects (
    rt_id        INTEGER PRIMARY KEY,
    id           BLOB NOT NULL UNIQUE,
    channel_id   BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    channel_key  INTEGER NOT NULL,
    kind         TEXT NOT NULL,           -- 'stroke' | 'image' | 'gif' | 'window'
    z_index      INTEGER NOT NULL DEFAULT 0,
    x            REAL NOT NULL DEFAULT 0,
    y            REAL NOT NULL DEFAULT 0,
    w            REAL NOT NULL DEFAULT 0,
    h            REAL NOT NULL DEFAULT 0,
    props        TEXT NOT NULL DEFAULT '{}',
    author_id    BLOB REFERENCES users(id) ON DELETE SET NULL,
    seq          INTEGER NOT NULL,
    is_encrypted INTEGER NOT NULL DEFAULT 0,
    created_at   INTEGER NOT NULL,
    deleted_at   INTEGER,
    UNIQUE (channel_id, seq)
) STRICT;

-- Catch-up by cursor and the whole-canvas snapshot both read this way; the
-- viewport path goes through the R-Tree instead.
CREATE INDEX canvas_objects_channel_live
    ON canvas_objects(channel_id, seq) WHERE deleted_at IS NULL;

CREATE VIRTUAL TABLE canvas_rtree USING rtree(
    rt_id,
    min_x, max_x,
    min_y, max_y,
    min_key, max_key
);

-- Triggers rather than an index write alongside each insert, for three
-- reasons that all come down to writes the application never sees: the
-- ON DELETE CASCADE from `channels` removes rows without any Rust code
-- running, Phase 6 materializes this table from an append-only op log and
-- compacts it on a schedule, and moderation deletes arrive by their own path.
-- A trigger also runs inside the same transaction as the write, so the index
-- cannot be left stale by a failure between two statements.
CREATE TRIGGER canvas_rtree_ai AFTER INSERT ON canvas_objects
WHEN NEW.deleted_at IS NULL BEGIN
    INSERT INTO canvas_rtree (rt_id, min_x, max_x, min_y, max_y, min_key, max_key)
    VALUES (NEW.rt_id, NEW.x, NEW.x + NEW.w, NEW.y, NEW.y + NEW.h,
            NEW.channel_key, NEW.channel_key);
END;

-- Scoped to the columns that can move an object or take it out of the world.
-- An unscoped trigger would rewrite the whole index when a deleted account's
-- authorship is nulled out, which touches every object that account ever made.
CREATE TRIGGER canvas_rtree_au
AFTER UPDATE OF x, y, w, h, channel_key, deleted_at ON canvas_objects BEGIN
    DELETE FROM canvas_rtree WHERE rt_id = OLD.rt_id;
    INSERT INTO canvas_rtree (rt_id, min_x, max_x, min_y, max_y, min_key, max_key)
    SELECT NEW.rt_id, NEW.x, NEW.x + NEW.w, NEW.y, NEW.y + NEW.h,
           NEW.channel_key, NEW.channel_key
    WHERE NEW.deleted_at IS NULL;
END;

CREATE TRIGGER canvas_rtree_ad AFTER DELETE ON canvas_objects BEGIN
    DELETE FROM canvas_rtree WHERE rt_id = OLD.rt_id;
END;
