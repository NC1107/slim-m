-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Backfills `channels.position`, dormant since 0002_core_schema.sql: the
-- column has existed on every deployment from the start, defaulted to 0 on
-- every row, and `Store::list_channels`'s own `ORDER BY position, created_at`
-- has therefore always fallen back to creation order. This assigns
-- sequential positions in that same order, so an upgrade does not reshuffle
-- anybody's rail; the first live reorder overwrites all of them at once.
-- DM channels are excluded: they are never listed or reordered by position.
WITH ordered AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY created_at, id) - 1 AS seq
    FROM channels
    WHERE deleted_at IS NULL AND kind != 'dm'
)
UPDATE channels
SET position = (SELECT seq FROM ordered WHERE ordered.id = channels.id)
WHERE id IN (SELECT id FROM ordered);
