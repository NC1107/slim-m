-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Deployment-wide settings an admin can change at runtime, as one row.
--
-- The first is the join policy. Registration has been invite-only since the
-- gate landed, with no way to change it, so an owner wanting an open community
-- had to hand out codes one at a time and a self-hoster could not open their
-- own Space at all.
--
-- `invite` is the default and is what every existing deployment gets on
-- upgrade: opening registration is a decision somebody makes, never something
-- a migration does to them. The CHECK is what keeps a typo from silently
-- reading as neither value and taking whichever branch the code happens to
-- write as its else.
CREATE TABLE space_settings (
    -- One row, enforced by the primary key rather than by convention.
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    join_policy TEXT NOT NULL DEFAULT 'invite' CHECK (join_policy IN ('invite', 'open')),
    updated_at  INTEGER NOT NULL
) STRICT;

INSERT INTO space_settings (id, join_policy, updated_at) VALUES (1, 'invite', 0);
