-- One shared execution result per fenced code block in a message, so everyone
-- viewing the message sees the latest run inline without rerunning it (a long
-- job runs once and its output is visible to all). Keyed by (message_id,
-- block_index) - the index of the fenced block within the message - and a
-- re-run replaces the row (last write wins), mirroring how a reaction row is
-- overwritten rather than versioned.
--
-- ran_by is nullable and SET NULL on account deletion: the shared output
-- outlives the account that produced it, the same way an anonymized author
-- leaves a message's author_id null rather than deleting the message.
CREATE TABLE code_runs (
    message_id  BLOB NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    block_index INTEGER NOT NULL,
    module_id   TEXT NOT NULL,
    command     TEXT NOT NULL,
    ok          INTEGER NOT NULL,
    output      TEXT NOT NULL,
    ran_by      BLOB REFERENCES users(id) ON DELETE SET NULL,
    ran_at      INTEGER NOT NULL,
    PRIMARY KEY (message_id, block_index)
) STRICT, WITHOUT ROWID;

-- The account-deletion sweep resolves ran_by to NULL by this column.
CREATE INDEX code_runs_ran_by ON code_runs(ran_by);
