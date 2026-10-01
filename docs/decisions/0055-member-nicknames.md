# 0055 - an administrator can give a member or bot a space-local name

Status: accepted, 2026-10-01.

## The report

The owner, on the live deployment:

> "unable to rename people/bots"

He is the administrator and wanted to rename other members and bots.
Until now the only name an account had was the one it chose for itself (`PATCH /me`), and a bot's `display_name` was fixed at creation.
No decision record covered nicknames or display names, so this is the first policy.

## Decision

A nickname is a name an administrator gives another account, valid inside this deployment only.
Because one deployment is one community, there is one nickname per account and every reader sees it.

- **Who may set one.** Anyone holding KICK_MEMBERS, under the same no-escalation rule as a timeout: not on yourself, not on an account whose granted permissions yours do not contain.
  No new permission was added.
  Renaming is the same tier of act as a timeout, changing how somebody else appears, and a separate bit would only be one more thing to grant.
- **Whom it applies to.** Members and bots alike.
  A bot's own `display_name` is fixed at creation, so a nickname is also how a bot is renamed afterwards.
- **Storage.** A `member_nicknames` side table, one row while a nickname is in force.
  `users.display_name` stays the account's own, so renaming is reversible and the hot `users` row does not grow.
- **What readers see.** `display_name` on `GET /users`, `GET /users/{id}` and `GET /members` is the nickname when there is one, so every surface that resolves a name from a profile follows without change.
  The DM list applies it too.
  `nickname` and `account_display_name` ride beside it.
- **Who sees the original.** Everyone.
  The member card shows `@username · account name X` whenever a nickname is set.
  Hiding the real name would let a nickname impersonate someone, and the username is already public.
  The renamed account reads `GET /me` unchanged, so its own settings and profile editor still show the name it chose.
- **Validation.** One to 64 characters after trimming, not blank, and none of the characters `crate::hidden_chars::is_hidden_char` refuses, the same `validate_label` a display name uses.
- **Audit.** `nickname_set` (the new name is the entry's `reason`) and `nickname_clear` in `moderation_audit_log`, written in the transaction that makes the change.
  Setting the name it already has writes and audits nothing.
- **Live update.** The change publishes `ProfileChanged`, which already makes every client re-resolve that account.

## Known edges

- Names the server bakes into a row at write time are not rewritten: a message's `author_display_name` and a voice roster entry's name read as the account's own until the client resolves the profile, which it does for message authors.
  That is the same staleness a self-rename has always had.
- Push notification text still uses the account's own name.
- The member card is the only place to rename from.
  The bots admin list still shows the account's own name.
