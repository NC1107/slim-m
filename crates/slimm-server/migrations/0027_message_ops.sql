-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- The message op stream: one row per real edit and one per real delete, dense
-- over its own `'message_op'` seq, so a client that has consumed up to `n` may
-- treat `n + 1` as the very next op that exists. `messages.seq` is untouched
-- and stays the ordering authority for creates, for keyset pagination and for
-- read state; this is a second, independent cursor over the same channel.
--
-- Pure DDL. The `'message_op'` counter row is allocated lazily by the write
-- path's upsert rather than backfilled here, so this migration writes nothing
-- to live data and no channel-creation path has to learn a new stream name.

CREATE TABLE message_ops (
    channel_id BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    seq        INTEGER NOT NULL,
    -- The column is spelled: 0024 turned `messages`'s primary key into
    -- `fts_rowid`, so a bare `REFERENCES messages` binds to that instead.
    message_id BLOB NOT NULL REFERENCES messages(id),
    kind       TEXT NOT NULL,
    -- Stored for the moderation record and never put on the wire.
    actor_id   BLOB REFERENCES users(id) ON DELETE SET NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (channel_id, seq),
    CONSTRAINT message_op_kind CHECK (kind IN ('edit', 'delete'))
) STRICT, WITHOUT ROWID;

-- Account deletion filters by actor.
CREATE INDEX message_ops_actor ON message_ops(actor_id) WHERE actor_id IS NOT NULL;

-- "Which ops touched this message", for the per-page content collapse.
CREATE INDEX message_ops_message ON message_ops(channel_id, message_id);
