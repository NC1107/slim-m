-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Rebuilds `canvas_ops` into the canvas's single ordering authority. The 0002
-- shape was one unconstrained `op TEXT` column and has never held a row on any
-- deployment: the only reference is the authorship anonymisation in
-- store/account_deletion.rs, which reads nothing. `canvas_objects` is
-- deliberately untouched, unlike 0015, which could rebuild it only because no
-- deployment held canvas rows yet.

DROP TABLE IF EXISTS canvas_ops_rebuild_guard;

CREATE TABLE canvas_ops_rebuild_guard (
    rows INTEGER NOT NULL CONSTRAINT canvas_ops_was_not_empty CHECK (rows = 0)
) STRICT;

INSERT INTO canvas_ops_rebuild_guard (rows) SELECT count(*) FROM canvas_ops;

DROP TABLE canvas_ops_rebuild_guard;
DROP TABLE canvas_ops;

CREATE TABLE canvas_ops (
    channel_id BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    seq        INTEGER NOT NULL,
    id         BLOB NOT NULL UNIQUE,
    kind       TEXT NOT NULL,
    actor_id   BLOB REFERENCES users(id) ON DELETE SET NULL,
    bound_seq  INTEGER,
    target_op  BLOB REFERENCES canvas_ops(id),
    created_at INTEGER NOT NULL,
    PRIMARY KEY (channel_id, seq),
    CONSTRAINT canvas_op_kind
        CHECK (kind IN ('place', 'remove', 'clear', 'restore')),
    CONSTRAINT canvas_op_bound
        CHECK ((kind = 'clear') = (bound_seq IS NOT NULL)),
    CONSTRAINT canvas_op_target
        CHECK ((kind = 'restore') = (target_op IS NOT NULL))
) STRICT, WITHOUT ROWID;

CREATE TABLE canvas_op_targets (
    channel_id BLOB NOT NULL,
    seq        INTEGER NOT NULL,
    object_id  BLOB NOT NULL REFERENCES canvas_objects(id),
    PRIMARY KEY (channel_id, seq, object_id),
    FOREIGN KEY (channel_id, seq)
        REFERENCES canvas_ops(channel_id, seq) ON DELETE CASCADE
) STRICT, WITHOUT ROWID;

-- Recreated, not inherited: DROP TABLE took 0019's index with it.
CREATE INDEX canvas_ops_author
    ON canvas_ops(actor_id) WHERE actor_id IS NOT NULL;

-- Restore reads "which objects did that op name", so the child table needs the
-- reverse lookup its own primary key already serves; this one serves the
-- forward lookup from an object to the ops that touched it, which is what
-- account deletion and any future audit read.
CREATE INDEX canvas_op_targets_object ON canvas_op_targets(object_id);
