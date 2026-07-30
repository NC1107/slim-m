-- SPDX-License-Identifier: AGPL-3.0-only
-- Who may link an already-uploaded attachment to a message they are sending.
--
-- Before this table, `link_attachments` authorized nothing: its only
-- predicate was that the sha256 existed anywhere in `attachments`, so anyone
-- who learned an attachment id (the content's own hash) could attach that
-- content to a message in any channel they could post in, whether or not
-- they ever uploaded it or could view where it was first shared.
--
-- A join table, not a single `uploader_id` column on `attachments`, because
-- `store_attachment` deduplicates by content hash
-- (`ON CONFLICT (sha256) DO UPDATE SET created_at = excluded.created_at`):
-- the same bytes uploaded twice are one row. A single overwritable
-- `uploader_id` would let the most recent re-uploader evict the original
-- uploader's linking rights; a single first-wins `uploader_id` would
-- permanently deny linking rights to a second person who genuinely uploads
-- the same bytes later (0013's own example: the same reaction gif, uploaded
-- twice, is exactly the case content addressing exists to share rather than
-- refuse). A join table has neither failure mode: every account that has
-- really uploaded these exact bytes keeps the right to link them, and
-- nobody else's re-upload can take that right away from anybody.
CREATE TABLE attachment_uploaders (
    sha256      BLOB NOT NULL REFERENCES attachments(sha256) ON DELETE CASCADE,
    uploaded_by BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    uploaded_at INTEGER NOT NULL,
    PRIMARY KEY (sha256, uploaded_by)
) STRICT, WITHOUT ROWID;
