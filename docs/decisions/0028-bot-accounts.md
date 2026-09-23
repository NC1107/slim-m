# 0028 - Bot accounts

Status: proposed (design; the server surface is built in stages after this record)
Date: 2026-09-19

## The ask

The owner, 2026-09-19: bots "would be like discord bots", so "spaces need to be able to authenticate bots and handle bots full crud permissions for within spaces", with "a new repo to manage bots or just provide a bot example and somewhere for the documentation on how to develope a bot".

The backlog card that reserved this work (2026-09-06) weighed two shapes and guessed the answer would lean on the module capability model.
That guess is superseded by the ask above.
A module is sandboxed wasm the host runs; it cannot be the thing an external process authenticates *as*.
A Discord-shaped bot is a program someone else deploys, which holds a credential and talks to the API.
So this record designs the second shape the card named: a bot is an account.

## What a bot is

**A bot is a user-shaped principal, not a parallel one.**

This is the whole design, and everything below follows from it.
A bot is a row in `users` with a `is_bot` flag, a UUIDv7 id like any other, no password hash (the column is already nullable), and a membership in the space.

The reason to do it this way is that slim already has one answer to every question a bot raises, and that answer is "the same as for a person":

- Who wrote this message? A `users.id`, which every read path already joins and every client already renders.
- What may it do here? Its roles, and the per-channel overrides on top of them (decision 0011), evaluated by the same `permissions_in_channel` every other action uses.
- What does it see on the socket? Exactly what its permissions allow, because `hub.rs` already authorizes fan-out per subscriber.
- Can a moderator stop it? Remove the member, or revoke its token. Both paths exist.
- What happens to its messages when it is deleted? The same as anyone's (decision 0016, and account deletion's anonymization).

A parallel bot principal would need a second answer to each of those, and second answers are where authorization bugs live.
So the flag is deliberately thin: it changes how a bot *authenticates* and how it is *labelled*, and nothing about how it is *authorized*.

The one place the thin flag was not enough: restoring a removed member. That path was written for a human and reasons "readmission restores the right to sign in, not the old credentials", which is correct for a human and vacuous for a bot, since a bot has no sign-in to retry and its token *is* its only credential. Left alone, that made restoring a removed bot a member-list fiction - it reappeared, and its token stayed permanently dead. The fix keeps the flag thin rather than adding a bot-shaped restore path: restoring a bot un-revokes the one session its live token still points at, scoped by that token's own `revoked_at`, so a token the operator revoked separately stays revoked. See `crates/slimm-server/src/store/removals.rs`.

The second place: listing.
`GET /bots` has no delete, by design.
Hard-deleting a bot's account would anonymize its authorship, which is exactly what "the account stays" above is protecting.
But nothing ever stopped `listBots` from returning a bot either, so a bot that was revoked and then removed from the Space stayed listed forever, with a dead token, after `GET /members` had already dropped it - a short true list about "what has a credential" answered "every bot ever minted" instead.
The fix is a filter, not a delete: `Store::list_bots` leaves out a bot removed from the Space by default, and `include_removed=true` still shows it, since removing it changed nothing about its account or its authorship.
A revoked bot that is still a member is never hidden, because it stays visible everywhere else (the member list, its own messages) and its authorship may be exactly why the row is worth reading.
See `crates/slimm-server/src/store/bots.rs::list_bots` and `GET /bots`'s `include_removed` parameter in `schema/openapi.yaml`.

Freeing a revoked bot's username for reuse is a separate question this record does not answer.
`DELETE /members/{id}/account` already exists for any removed account, bot or human, and already frees the username on deletion - but it also anonymizes authorship, the opposite of what a bot's revocation promises.
Nothing here stops an administrator from pointing it at a bot; whether it should refuse a bot target, or a bot should get some other way to give its name back, is unresolved.

"Full CRUD permissions within spaces", then, is not a new subsystem.
It is giving the bot a role with the bits it needs, out of the eighteen that already exist.
A fresh bot holds whatever `@everyone` holds in that space and nothing more - default-deny, as with any new member.

## Authentication: a long-lived, revocable bot token

A bot does **not** use the access/refresh session pair.

Sessions rotate, and rotation assumes a client that can persist the new pair and, if that goes wrong, a person who can sign in again.
A bot is typically a container with a credential in an environment variable.
It has nowhere to persist a rotated token and nobody at a keyboard to recover, which is exactly the failure this project has already been bitten by from the other end (decision 0024, and the lost-rotation sign-out fixed in #1232).
Rotation would convert every dropped response into a dead bot.

So a bot token is:

- **Long-lived and non-rotating.** One credential, valid until revoked.
- **Hashed at rest**, with the same `hash_secret` every other credential uses. Shown once, at creation, and never retrievable again - the same one-time-reveal shape the admin reset codes already use.
- **Named**, so an operator with several can tell them apart, and **revocable individually**.
- **Provisioned by a member holding `MANAGE_SERVER`**, and every creation and revocation goes on the moderation-audit trail (decision 0015).
- **Presented as `Authorization: Bearer <token>`**, resolved by the same auth extractor, against its own table rather than `access_tokens`.

The mitigation for a long-lived credential is revocation and audit, not a short TTL.
That is a deliberate trade: the token's blast radius is bounded by the bot's *permissions*, which is the control that actually matters, and which a short TTL would not tighten.

A bot receives events over the existing WebSocket, minting a `ws_ticket` with its token exactly as a client mints one with a session.
No new transport.

## What a bot may never do

Three limits are part of the contract rather than the implementation:

- **A bot acts only as itself.** It can never act on another user's behalf, and there is no impersonation parameter anywhere in the surface. This is the sharpest contrast with decision 0023's module capabilities, which deliberately *do* act as the invoking user. A module runs because a person asked it to, inside the host, in that person's context; a bot runs because its operator started it, outside the host, as itself.
- **A bot cannot provision bots.** Token creation requires `MANAGE_SERVER` held by a human member; a bot holding that bit still cannot mint bot tokens, so a compromised bot cannot fork itself into a second credential that survives revoking the first.
- **A bot is not exempt from anything.** Not slow mode, not message retention, not moderation, not per-channel overrides. Where a limit applies to a member it applies to a bot, and where a bot needs a different *budget* that is a rate-limit class, not an exemption.

## Rate limits

Bot traffic is keyed by the **bot's own id**, never by IP.
A bot is a server: its address says nothing about who is calling, and several bots behind one host must not share a bucket.

Bots ride the existing classes with their own budgets, because the shapes differ from a person's: a bot reads and writes steadily rather than in bursts around human attention, and one busy bot must not crowd out the people in a space.
The concrete budgets are sized when the surface is built, against the same reasoning the existing variants document, not guessed here.

## Identity in the interface

A bot appears in the member list and as a message author, with a **BOT badge** beside its name - drawn from the existing design tokens, never an emoji (the interface rule in `docs/design/design-language.md`).
The badge is the one affordance that matters: a reader has to be able to tell that something was written by a program without inspecting anything.

Presence is honest: a bot is online when its socket is connected and offline when it is not.
It does not get a special presence state, and it can be hidden like anyone (decision on presence visibility already allows this).

## Staging

Each stage is shippable and reviewable alone, and nothing before the last one is visible to a bot author:

1. **Identity.** `users.is_bot`, the badge, and the member-list and author-surface reading of it. No auth yet, so nothing can log in as one.
2. **Tokens.** The `bot_tokens` table, provisioning and revocation behind `MANAGE_SERVER`, audit entries, and the auth extractor resolving a bot token to a `SessionContext`.
3. **Admin UI.** Creating, naming, listing and revoking tokens, with the one-time reveal.
4. **Rate-limit classes** sized for bot traffic.
5. **SDK, example and docs**, so somebody outside this repo can actually write one.

Stage 5 is where the owner's "new repo or an example plus docs" question lands.
The reversible answer is taken first: the guide lives in this repo as `docs/bots/building-bots.md`, mirroring `docs/modules/building-modules.md`, and a minimal runnable example beside it.
Promoting the example into a repo of its own is a decision to make once there is something worth promoting, and it is the owner's to make - a public repository under their account is not a thing this record creates on its own.

## What this record does not decide

- Whether a bot may be installed from some registry, or only provisioned by hand. Hand-provisioned, for now, because there is no registry.
- Slash commands owned by a bot. The module system already owns that extension point (decision 0021); whether a bot may register one is a later, additive question.
- Whether bots may hold `ADMINISTRATOR`. The permission system has no special cases and this record adds none, so the bit is grantable; whether that should be refused outright is a product call, and the audit trail is what makes it visible in the meantime.
