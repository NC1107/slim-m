-- SPDX-License-Identifier: AGPL-3.0-only
--
-- Two fixes found by an audit of the phase 3 backbone.
--
-- 1. sessions had an index on user_id but none on device_id, while push
--    fan-out and every device-scoped revocation path filter by device_id.
--    Those queries were full table scans over a table that only ever grows.
--
-- 2. The FTS5 triggers were asymmetric. The insert trigger is guarded by
--    `WHEN NEW.is_encrypted = 0`, so an encrypted message is deliberately
--    never added to the index; the delete and update triggers issue their
--    FTS5 'delete' unconditionally. Telling an external-content FTS5 table to
--    delete a rowid it never held corrupts the index, which is exactly what
--    SQLite's own documentation warns against for a partial index. It is
--    dormant today only because nothing sets is_encrypted to 1 yet, so it
--    would first appear when opt-in E2EE lands, as search quietly returning
--    wrong rows. Fixed now, while the table it protects is still empty of
--    encrypted rows and no rebuild is needed.

CREATE INDEX sessions_device ON sessions(device_id);

DROP TRIGGER messages_fts_ad;
DROP TRIGGER messages_fts_au;

-- Mirror the insert trigger's guard: only ever delete what was indexed.
CREATE TRIGGER messages_fts_ad AFTER DELETE ON messages WHEN OLD.is_encrypted = 0 BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', OLD.rowid, OLD.content);
END;

-- An update can cross the boundary in either direction, so each side carries
-- its own guard rather than one guard on the whole trigger: remove the old row
-- only if it was indexed, add the new one only if it should be.
CREATE TRIGGER messages_fts_au AFTER UPDATE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content)
        SELECT 'delete', OLD.rowid, OLD.content WHERE OLD.is_encrypted = 0;
    INSERT INTO messages_fts(rowid, content)
        SELECT NEW.rowid, NEW.content WHERE NEW.is_encrypted = 0;
END;
