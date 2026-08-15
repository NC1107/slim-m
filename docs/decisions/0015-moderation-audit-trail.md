# 0015 - Moderation keeps its history in a log, not in the tables that hold current state

Date: 2026-08-15
Status: accepted, implemented

## What was wrong

`space_removals` and `member_timeouts` each hold one row per member, and undoing either deletes the row.
`restore_to_space` and `clear_member_timeout` were both a bare `DELETE`, so lifting a ban destroyed the only record that it had ever happened: which moderator imposed it, on whom, and why.
A re-issued timeout overwrote its predecessor for the same reason.

The canvas had solved this exact problem a migration earlier.
`canvas_audit_log` (0037) exists because a compacting op stream was destroying "who removed what", and it kept the fact in a separate append-only table.
Moderation had nothing equivalent - it was the only part of the product where an act could be erased by the act that reversed it.

Recorded as MOD3 in `TECHNICAL_DEBT.md`, High.

## The fix that was recorded, and why it is not the one shipped

The debt entry prescribed soft-closing: add `lifted_at` and `lifted_by` to the two tables and mark rows instead of deleting them.
That reads like a two-column change. It is not, and each of the three reasons was verified against the source rather than reasoned about.

**`user_id` is the primary key on both tables.**
So a member can only ever have one row, and history needs a surrogate key plus a partial unique index to keep "one open act per member".
Changing a primary key in SQLite is a table rebuild, on two tables, one of which the login path reads.

**Both writers upsert.**
`remove_from_space` and `set_member_timeout` both use `ON CONFLICT(user_id) DO UPDATE`.
Once a lifted row is left in place, a second removal of the same member updates that row and leaves `lifted_at` set: the removal returns 204, the sessions are revoked, and the member signs straight back in, because every read still treats the row as lifted.
A silent moderation bypass, and every existing test stays green through it.

**Fifteen statements read these tables, not the six the entry implies.**
Each would need `AND lifted_at IS NULL`, and two of them fail in ways that are very hard to recover from on a self-hosted deployment with no support channel.
`sessions.rs` gates login on `NOT EXISTS (SELECT 1 FROM space_removals WHERE user_id = ?)`, so missing it locks every reinstated member out permanently.
`roles.rs`'s `administrator_count` is the last-administrator guard, so missing it lets a Space be walked down to zero reachable administrators one removal at a time - the failure that guard exists to prevent, and which shipped once already.
A third, `timed_out_among_until`, is built with `QueryBuilder` rather than a macro, so it is absent from `.sqlx/` and invisible to any review that greps for query macros.

The entry also reverses a decision that is written down in a shipped, immutable migration.
`0020_member_timeouts.sql` says: "One row per member rather than a history: this table answers 'is this person timed out right now'".
That decision is correct. What was missing was never a second row in that table.

## Decision

**Live tables answer "what is in force now". Append-only logs answer "what happened". No read joins the two.**

`0048_moderation_audit_log.sql` adds one table, shaped after `canvas_audit_log`: surrogate `INTEGER PRIMARY KEY`, nullable `actor_id` anonymized on account deletion, an `action` CHECK over `remove`, `restore`, `timeout` and `timeout_cleared`, a `(subject_id, created_at)` index for one member's history, and a partial `actor_id` index for the deletion filter.
It backfills everything in force at upgrade time so the log does not open by implying nothing had happened.

`space_removals` and `member_timeouts` are untouched, as are all fifteen reads.
Each of the four write paths appends one row inside the same transaction as the state change it records, so a refused removal leaves neither.
The two undo paths only log when they actually undid something; both are documented as idempotent, and recording a no-op would put an act in the trail that never happened.

`restore_to_space` and `clear_member_timeout` gained the acting moderator as a parameter. Both callers already held it.

## What this costs, accepted deliberately

Soft-closing cannot drift. The state *is* the history, because they are the same row.

This can. Nothing in the schema forces a write to `space_removals` or `member_timeouts` to also write the log; the invariant lives in the discipline of going through the four store functions.
A future bulk-unban tool, an admin CLI, or a fifth write path added by somebody who has not read `store/moderation_audit.rs` will leave the log quietly under-reporting, and nothing will fail until a moderator needs the record and it is not there.
That is the same class of failure as the `ON DELETE SET NULL` clauses in 0020 and 0021, which read as though the constraint does the work and in fact can never fire, because account deletion is a tombstone `UPDATE` and never a `DELETE FROM users`.

The trade was taken on the judgement that drift is slow, visible in review, and correctable by a later migration, while a lockout is none of those things.
Being wrong about the login gate locks real people out of a deployment that has nobody to appeal to.

Mitigations taken now: `record_moderation_audit` is `pub(super)` so it cannot be called from outside the store, the four writers remain the only write path, and `moderation_audit.rs` says in its own doc comment what it is for.
If drift ever does materialise, a trigger on the two live tables is available as hardening without another rebuild.

## Consequences

MOD4, an owner-visible moderation history, now has a single ordered feed to read rather than two tables to union with a `lifted_at IS NOT NULL` filter over rows that are simultaneously the live-state rows.

Nothing reads the table over HTTP yet, which is the shape `canvas_audit_log` also started in and which 0037 defends: the writer has to exist before the reader has anything to show.
There is no route, no DTO and no `schema/openapi.yaml` change in the change that introduced it.

A timeout that simply lapses writes nothing.
Only an explicit lift records a `timeout_cleared`, so a timeout that ran its course leaves just its original `timeout` row, carrying the deadline it ran to.
That follows from 0011's decision that a lapse "expires by arithmetic, nothing runs and nothing is published" - there is no moment at which anything could write the row, and inventing a sweep to create one would mean running a job purely to log that time had passed.
The deadline is already on the issue row, so the history is not missing anything; it is stated here because "no entry" and "nothing happened" look alike otherwise.

There is no sweep. `canvas_audit_log` carries none either, for the same reason: outliving the thing that gets deleted is the point of the table.
One row per moderation act on a deployment sized for a friend group is not a growth problem, and a retention policy is a decision to make when somebody has a reason for one rather than now.

`MOD3`'s entry in `TECHNICAL_DEBT.md` was corrected in the same change, so it stops prescribing the design that was rejected here.
