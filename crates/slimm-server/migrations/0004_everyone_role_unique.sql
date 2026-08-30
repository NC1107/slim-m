-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Enforce the single-@everyone-role invariant the permission evaluator depends on.
--
-- The base of every permission evaluation is the one role with is_everyone = 1.
-- Without a constraint, a second such role could be created and the loader would
-- pick one of them nondeterministically, silently changing the effective
-- permissions of every member. This partial unique index makes a second
-- @everyone role fail at the database instead.
CREATE UNIQUE INDEX roles_one_everyone ON roles(is_everyone) WHERE is_everyone = 1;
