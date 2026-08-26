# 0016 - Message deletion has no hierarchy, and no appeal path exists in the product

Date: 2026-08-15
Status: accepted, implemented

Two owner decisions, recorded together because both answer the same underlying question: how far a moderator's reach goes, and what the person on the other end of it can do about it.

## Deleting messages is not ranked

`MANAGE_MESSAGES` in a channel reaches every message in that channel, including an administrator's. There is no containment rule on message deletion and there will not be one.

This was settled after briefly shipping the opposite. `POST /channels/{channelId}/messages/bulk-delete` (#675) carried an `escalation_guard`, the rule that refuses when the caller's granted permissions do not contain the target's, and which already guards role edits, member moderation and voice kicks. It was removed in the change that follows this record.

The reason is that the guard did not protect anything. `deleteMessage` has never had it: a member holding `MANAGE_MESSAGES` can delete an administrator's message today, one request at a time, and always could. A guard on the bulk route alone would have refused sixty-four at once while allowing the same sixty-four one after another. That is a difference in patience, not in permission, and a rule that is sidestepped by working more slowly is worse than no rule - it reads as protection to whoever finds it and offers none to whoever needed it.

The honest framing is that `MANAGE_MESSAGES` is already the strong bit. Granting it is the decision; what it reaches afterwards is not separately negotiable. `docs/research/audit-2026-07-30/server-code.md` records that this product has no role hierarchy and uses permission containment where ranking is needed - moderation of *people* is ranked, because removing or timing out a member acts on them rather than on what they wrote. Deleting a message is not that.

Consequences accepted deliberately:

- A moderator can remove an administrator's messages, in bulk or singly. If that is not wanted for a given person, the answer is not to grant them `MANAGE_MESSAGES`, or to scope it to a channel with a channel overwrite - which decision 0011 already makes possible per channel.
- `moderation_audit_log` records every such act with its actor, which is the check that matters here: not preventing the reach, but making it visible afterwards. That is what MOD3 and migration 0048 exist for.

## There is no in-product appeal path

A removed member cannot sign in at all - `open_session` refuses to create a session for them - and a timed-out member keeps their session but has `SEND_MESSAGES` subtracted everywhere including DMs, so they cannot message a moderator either.

That stays as it is. No appeal route, no exemption for DMs to a moderator, no read-only mode for a removed account.

Recorded as MOD5 in the technical-debt register of the time (since retired; see the Planka board), where its own entry said the question was a product decision rather than a defect: "Whether an in-product appeal path is wanted at all is a product decision, not a defect; recorded because 'no route back' is currently implicit rather than chosen." It is now chosen.

The reasoning is the shape of the product rather than a judgement about appeals in general. One deployment is one community, usually a group who know each other; the operator and the moderators are reachable by whatever means the group already uses, and building a channel back into a space somebody has been removed from means keeping a door open in exactly the place a removal is meant to close one. A raid is the case moderation here is sized for, and an appeal inbox reachable by removed accounts is a surface a raid can use.

Consequences accepted deliberately:

- A wrongly removed member has no in-product recourse. An administrator can restore them (`DELETE /members/{userId}/removal`), and since MOD3 that restoration is recorded with who did it - so the correction is possible and visible, just not self-service.
- A timed-out member cannot ask why. The reason is captured on the timeout and is not shown to them; that gap is MOD6 and is worth closing on its own merits, since a person who can see why they were silenced needs to ask about it less.

## What would reopen either

For the first: a deployment where `MANAGE_MESSAGES` is handed out widely enough that reaching an administrator's messages is a real risk rather than a theoretical one. Nothing in the product pushes that way today, and channel overwrites are the pressure valve if it ever does.

For the second: a deployment large enough that its moderators are not otherwise reachable. That is a different product from the one `docs/BRIEF.md` describes, and the decision should be revisited whole rather than patched with a DM exemption.
