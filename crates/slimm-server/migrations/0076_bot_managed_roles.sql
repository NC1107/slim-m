-- SPDX-License-Identifier: AGPL-3.0-only
-- A bot's managed role: the role minted alongside a bot at creation, holding
-- exactly the permissions its provisioner approved, and removed when the bot
-- is revoked. See docs/decisions/0028-bot-accounts.md.
--
-- managed_bot_id names the bot this role belongs to. A plain ALTER TABLE ADD
-- COLUMN is enough here, unlike 0049's rebuild: this column is nullable with
-- no non-constant default, which SQLite's restricted ADD COLUMN already
-- allows, REFERENCES clause included.
--
-- ON DELETE CASCADE so a hard user delete (never used on a bot today, but not
-- structurally forbidden) takes its managed role with it rather than leaving
-- a role with a dangling managed_bot_id. Ordinary bot revocation is a
-- token/session revoke, not a user delete, so it does not go through this
-- cascade; crates/slimm-server/src/store/bots.rs deletes the managed role by
-- hand in the same transaction as the revoke, for the same
-- write-and-its-trail-together reason 0015 already applies to moderation.
--
-- A UNIQUE index rather than a UNIQUE column constraint: SQLite's ALTER TABLE
-- ADD COLUMN refuses a UNIQUE constraint on the new column outright, so the
-- same one-role-per-bot invariant is expressed as a separate partial index
-- instead, matching the shape roles.is_everyone's own singleton index
-- already uses in 0002_core_schema.sql.
ALTER TABLE roles ADD COLUMN managed_bot_id BLOB REFERENCES users(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX roles_managed_bot ON roles(managed_bot_id) WHERE managed_bot_id IS NOT NULL;
