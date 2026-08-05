-- SPDX-License-Identifier: AGPL-3.0-only
-- Links an already-uploaded attachment to a canvas object, the `message_attachments`
-- shape carried over to a second placement surface: a pasted image is
-- content-addressed and never re-attached to a message, so nothing else in
-- the schema records that a channel's canvas is what makes these bytes
-- fetchable to anyone but the uploader.
--
-- `object_id` is not scoped to `deleted_at IS NULL`: an erased image can be
-- brought back by a `restore` op, and the attachment sweep must not reclaim
-- bytes a still-existing (if currently soft-deleted) object row could need
-- again. The row is written once, at placement, and never removed - the
-- same permanence `canvas_objects` itself never hard-deletes.
CREATE TABLE canvas_object_attachments (
    object_id BLOB NOT NULL REFERENCES canvas_objects(id),
    sha256    BLOB NOT NULL REFERENCES attachments(sha256),
    PRIMARY KEY (object_id, sha256)
) STRICT, WITHOUT ROWID;

-- The reverse lookup `channels_referencing_attachment` and the orphan sweep
-- both need: from a content hash to whichever object(s) reference it.
CREATE INDEX canvas_object_attachments_sha256 ON canvas_object_attachments(sha256);
