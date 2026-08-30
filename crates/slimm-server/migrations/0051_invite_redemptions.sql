-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Which user redeemed which invite code, so a redemption is idempotent per
-- (code, user). `spend_invite`'s conditional UPDATE guards the code's own use
-- limit, expiry and revocation, but nothing recorded whether this caller had
-- already redeemed it: a retry after a lost response spent a second real use
-- on a limited invite, or reported failure for a max_uses=1 redemption that
-- had in fact succeeded. This table is the (code, user) key that makes a
-- repeat a no-op; see SRV5 and `Store::redeem_invite`.
--
-- Both spend paths write here - redemption by an existing account and a code
-- used at registration - so a user who joined with a code cannot then redeem
-- the same code again for a second use. Account deletion is a tombstone, not a
-- DELETE FROM users, so its ON DELETE CASCADE never fires for that path;
-- `delete_account` purges these rows by hand alongside the account's other
-- per-user tables, so a redemption never outlives the account it names.

CREATE TABLE invite_redemptions (
    code        TEXT NOT NULL REFERENCES invites(code) ON DELETE CASCADE,
    user_id     BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    redeemed_at INTEGER NOT NULL,
    PRIMARY KEY (code, user_id)
) STRICT, WITHOUT ROWID;
