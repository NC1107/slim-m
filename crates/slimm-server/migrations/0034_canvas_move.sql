-- SPDX-License-Identifier: AGPL-3.0-only
-- Adds `move` to `canvas_ops`: repositioning a placed object without erasing
-- it, so a pasted image is not nailed permanently to wherever it first
-- landed. SQLite cannot widen a CHECK constraint in place, and unlike 0026's
-- rebuild this table now holds real rows (`remove`/`clear`/`restore` have
-- shipped since), so this is a rebuild against live data rather than an
-- empty-table replacement.
--
-- `canvas_op_targets` has to be saved aside and restored, the exact shape
-- 0024's `messages` rebuild used for its own cascade-reachable children, and
-- for the same reason: its FK is `ON DELETE CASCADE REFERENCES
-- canvas_ops(channel_id, seq)`, and SQLite fires that cascade for a DROP
-- TABLE exactly as it would for a DELETE, under foreign_keys=ON, which this
-- connection runs with throughout. The first version of this migration
-- dropped `canvas_ops` directly and lost every `remove`/`restore` target row
-- in the process - caught by testing the migration against a seeded
-- database rather than only a fresh one, not by reasoning about it first.
-- SELECT * is the point of a wholesale snapshot; naming columns would drift from the source.
CREATE TABLE canvas_op_targets_rebuild AS SELECT * FROM canvas_op_targets; -- NOSONAR
CREATE TABLE canvas_ops_rebuild AS SELECT * FROM canvas_ops; -- NOSONAR

DELETE FROM canvas_op_targets; -- NOSONAR
DROP TABLE canvas_ops;

CREATE TABLE canvas_ops (
    channel_id BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    seq        INTEGER NOT NULL,
    id         BLOB NOT NULL UNIQUE,
    kind       TEXT NOT NULL,
    actor_id   BLOB REFERENCES users(id) ON DELETE SET NULL,
    bound_seq  INTEGER,
    target_op  BLOB REFERENCES canvas_ops(id),
    -- Only a `move` sets these four together; see `canvas_op_move_bounds`.
    move_x     REAL,
    move_y     REAL,
    move_w     REAL,
    move_h     REAL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (channel_id, seq),
    CONSTRAINT canvas_op_kind
        CHECK (kind IN ('place', 'remove', 'clear', 'restore', 'move')),
    CONSTRAINT canvas_op_bound
        CHECK ((kind = 'clear') = (bound_seq IS NOT NULL)),
    CONSTRAINT canvas_op_target
        CHECK ((kind = 'restore') = (target_op IS NOT NULL)),
    CONSTRAINT canvas_op_move_bounds
        CHECK ((kind = 'move') = (move_x IS NOT NULL AND move_y IS NOT NULL
                                   AND move_w IS NOT NULL AND move_h IS NOT NULL))
) STRICT, WITHOUT ROWID;

INSERT INTO canvas_ops (channel_id, seq, id, kind, actor_id, bound_seq, target_op, created_at)
    SELECT channel_id, seq, id, kind, actor_id, bound_seq, target_op, created_at
    FROM canvas_ops_rebuild;

CREATE INDEX canvas_ops_author
    ON canvas_ops(actor_id) WHERE actor_id IS NOT NULL;

-- Restored only now that every (channel_id, seq) it references exists again.
INSERT INTO canvas_op_targets (channel_id, seq, object_id)
    SELECT channel_id, seq, object_id FROM canvas_op_targets_rebuild;

CREATE TABLE canvas_ops_rebuild_guard (
    ops     INTEGER NOT NULL CONSTRAINT canvas_ops_row_count_changed CHECK (ops = 0),
    targets INTEGER NOT NULL CONSTRAINT canvas_op_targets_row_count_changed CHECK (targets = 0)
) STRICT;
INSERT INTO canvas_ops_rebuild_guard (ops, targets) VALUES (
    (SELECT count(*) FROM canvas_ops) - (SELECT count(*) FROM canvas_ops_rebuild),
    (SELECT count(*) FROM canvas_op_targets) - (SELECT count(*) FROM canvas_op_targets_rebuild)
);
DROP TABLE canvas_ops_rebuild_guard;

DROP TABLE canvas_ops_rebuild;
DROP TABLE canvas_op_targets_rebuild;
