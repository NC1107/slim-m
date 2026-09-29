-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Marks a forward whose original was deleted or aged out, for a copy that
-- carries the forwarder's own note.
--
-- A copy with nothing of its own is soft-deleted with the original. One with
-- a note or attachments keeps the forwarder's words, so only the snapshot of
-- someone else's content goes: origin_content is blanked, the author is
-- dropped, and this column says why the card is empty.
ALTER TABLE message_forwards ADD COLUMN origin_removed_at INTEGER;
