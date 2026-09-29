-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Finds the copies of a message when it is deleted or ages out.
--
-- 0059 left origin_message_id unindexed because nothing looked a forward up
-- by its origin. Deleting the original now removes its copies, and that is a
-- lookup by this column on every delete and every retention prune.
CREATE INDEX message_forwards_origin_message ON message_forwards(origin_message_id);
