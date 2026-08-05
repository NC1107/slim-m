-- SPDX-License-Identifier: AGPL-3.0-only
-- Adds `reorder` to `canvas_ops`: changing which object paints on top
-- without touching its position, so two overlapping images have a way to
-- swap which one is in front. `z_index` is not part of the R-Tree (only
-- `x, y, w, h, channel_key` are named in 0015's `UPDATE OF` trigger clause),
-- so this rebuild carries no R-Tree consequence at all, unlike 0034's own
-- rebuild for `move`.
--
-- This is a rebuild against live data, not an empty-table replacement, the
-- exact same reason and the exact same shape 0034 used: `canvas_op_targets`
-- has to be saved aside and restored around the `DROP TABLE`, because its FK
-- is `ON DELETE CASCADE REFERENCES canvas_ops(channel_id, seq)` and SQLite
-- fires that cascade for a `DROP TABLE` under `foreign_keys=ON`, which this
-- connection runs with throughout.
-- Columns named rather than starred, for the same reason 0034 gives: a
-- migration runs against one known prior schema, so this documents exactly
-- what is preserved.
CREATE TABLE canvas_op_targets_rebuild AS
    SELECT channel_id, seq, object_id FROM canvas_op_targets;
CREATE TABLE canvas_ops_rebuild AS
    SELECT channel_id, seq, id, kind, actor_id, bound_seq, target_op,
           move_x, move_y, move_w, move_h, created_at
    FROM canvas_ops;

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
    -- Only a `reorder` sets this; see `canvas_op_reorder_z`.
    reorder_z  INTEGER,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (channel_id, seq),
    CONSTRAINT canvas_op_kind
        CHECK (kind IN ('place', 'remove', 'clear', 'restore', 'move', 'reorder')),
    CONSTRAINT canvas_op_bound
        CHECK ((kind = 'clear') = (bound_seq IS NOT NULL)),
    CONSTRAINT canvas_op_target
        CHECK ((kind = 'restore') = (target_op IS NOT NULL)),
    CONSTRAINT canvas_op_move_bounds
        CHECK ((kind = 'move') = (move_x IS NOT NULL AND move_y IS NOT NULL
                                   AND move_w IS NOT NULL AND move_h IS NOT NULL)),
    CONSTRAINT canvas_op_reorder_z
        CHECK ((kind = 'reorder') = (reorder_z IS NOT NULL))
) STRICT, WITHOUT ROWID;

INSERT INTO canvas_ops (channel_id, seq, id, kind, actor_id, bound_seq, target_op,
                         move_x, move_y, move_w, move_h, created_at)
    SELECT channel_id, seq, id, kind, actor_id, bound_seq, target_op,
           move_x, move_y, move_w, move_h, created_at
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
