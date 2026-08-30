-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Threads resolve through their parent message, and open_thread's duplicate
-- check (WHERE parent_message_id = ?) had no index reaching the column, so
-- every thread open scanned the whole channels table. Partial, the same
-- shape canvas_ops_author uses: almost every channel row is not a thread,
-- and the NULL rows are exactly the ones no lookup here ever wants.
CREATE INDEX channels_parent_message ON channels(parent_message_id)
    WHERE parent_message_id IS NOT NULL;
