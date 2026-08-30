-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Removing somebody from the Space, which has to be a durable row because
-- there is no membership row to delete.
--
-- One deployment is one community and holding an account *is* membership, so
-- there is nothing to remove in the way a multi-guild product would remove a
-- guild member. The honest shape is therefore a standing refusal: sign-in is
-- refused, live sessions are revoked, and the member list stops listing them.
--
-- Durable rather than a one-off session revocation on purpose. A revocation
-- that only closed today's sockets would be undone by signing in again, which
-- on an open Space is one form submission away and on an invite-only Space
-- still leaves the account itself working. So this is a ban in behaviour, and
-- naming it "removal" in the UI does not change that; `deploy/README.md` says
-- as much rather than leaving an operator to discover it.
--
-- Reversible by deleting the row, because a moderator acting in anger at
-- 2am is the normal case and an irreversible button would be the wrong tool
-- for a friend group.
--
-- What this deliberately does NOT do is stop the same person registering a
-- fresh account on an open Space. Nothing short of identity verification
-- would, that is well outside a self-hosted friend group's threat model, and
-- pretending otherwise would be worse than saying so.
--
-- Authored messages stay exactly where they are: removing somebody is not a
-- reason to rewrite a conversation other people were part of. Deleting the
-- account is the separate, already-built thing that does that.
CREATE TABLE space_removals (
    user_id    BLOB PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    reason     TEXT,
    -- Null once the moderator's own account is deleted, same as a timeout.
    removed_by BLOB REFERENCES users(id) ON DELETE SET NULL,
    removed_at INTEGER NOT NULL
) STRICT;
