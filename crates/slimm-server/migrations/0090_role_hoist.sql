-- SPDX-License-Identifier: AGPL-3.0-only
-- Whether the member pane lists this role's members under their own heading.
-- New roles default off, so a role stays out of the pane's sections until
-- whoever holds MANAGE_ROLES opts it in. Existing roles are backfilled on,
-- unlike that default, because before this column the pane sectioned by every
-- member's top role: the backfill keeps the pane looking as it did before the
-- migration. `@everyone` is excluded, as it never was a section.
ALTER TABLE roles ADD COLUMN hoist INTEGER NOT NULL DEFAULT 0;
UPDATE roles SET hoist = 1 WHERE is_everyone = 0;
