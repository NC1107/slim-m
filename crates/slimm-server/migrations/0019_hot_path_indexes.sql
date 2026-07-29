-- Indexes for scans that grow with content, found by a database audit.
--
-- Account deletion anonymizes authored content with three UPDATE ... WHERE
-- author_id = ? statements (store/sessions.rs), each a full table scan while
-- holding SQLite's single write lock; messages and canvas rows are exactly
-- the tables that grow without bound, so deleting an account on a busy
-- deployment stalls every other write for the duration. Partial indexes
-- exclude already-anonymized rows, which after deletion is most of them.
--
-- The hourly orphaned-attachment sweep filters created_at with no index, and
-- the expired-token sweeps batch by rowid over unindexed expires_at, which on
-- a backlog re-scans what earlier batches already passed over.

CREATE INDEX messages_author ON messages(author_id) WHERE author_id IS NOT NULL;
CREATE INDEX canvas_objects_author ON canvas_objects(author_id) WHERE author_id IS NOT NULL;
CREATE INDEX canvas_ops_author ON canvas_ops(author_id) WHERE author_id IS NOT NULL;

CREATE INDEX attachments_created_at ON attachments(created_at);

CREATE INDEX access_tokens_expiry ON access_tokens(expires_at);
CREATE INDEX refresh_tokens_expiry ON refresh_tokens(expires_at);
CREATE INDEX ws_tickets_expiry ON ws_tickets(expires_at);
