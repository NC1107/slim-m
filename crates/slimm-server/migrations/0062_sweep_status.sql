-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- One row per background sweep, so an operator's storage view can show when
-- each last ran and how much it reclaimed, rather than only finding out a
-- sweep exists once disk fills up. `name` is a stable snake_case identifier
-- ("token", "attachments", "canvas_ops", "message_retention"); a sweep that
-- has never run yet simply has no row here.
CREATE TABLE sweep_status (
    name           TEXT NOT NULL PRIMARY KEY,
    last_run_at    INTEGER NOT NULL,
    last_reclaimed INTEGER NOT NULL DEFAULT 0
) STRICT;
