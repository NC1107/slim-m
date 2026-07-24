# Database Plan: Adversarial Review

Target document: `docs/research/database.md`.
This is a fresh review pass, cross-checked against `docs/BRIEF.md`, `docs/decisions/0001-owner-decisions.md`, `docs/research/stack-decision.md`, and the sibling reports `docs/research/security.md`, `docs/research/realtime-sync.md`, `docs/research/voice-canvas.md`, and `docs/research/appstore.md`.
The echo-messenger repository was not read and no finding below is based on it.

Severity key: critical findings would force a redesign of a foundational piece of the plan as written.
Major findings are real defects that should block sign-off until addressed.
Minor findings are worth fixing but do not block the overall direction.

## Critical findings

### 1. `channel_seq_counters` cannot actually serve the two scopes Section 4 says it serves

Target: Section 4, "Every ordered stream (a channel's messages, a channel's canvas ops) is its own scope, with `seq` assigned from `channel_seq_counters` inside the same transaction as the insert," against the schema `channel_seq_counters(channel_id, next_seq)`.

Weakness: the prose names two distinct scopes per channel, a channel's messages and a channel's canvas ops, and calls each "its own scope."
A scope needs its own independent, gap-free counter for that claim to hold.
The table given has one row per `channel_id` with a single `next_seq` column, no stream discriminator, and no way to hold two independent counters for one channel.
As written, `messages.seq` and `canvas_ops.seq` for the same channel can only be drawing from the same shared counter, interleaved across two different tables, or the table is simply incomplete.

Failure mode: if the counter is shared, every canvas op committed in a channel consumes a number that never appears in `messages.seq`, so a client tracking only the message stream sees non-contiguous values, for example 1, 2, 5, 6, whenever canvas activity happened in between.
`realtime-sync.md`'s own resync trigger is explicit and depends on exactly the guarantee this breaks: "because sequence is contiguous per scope, a client that sees a jump greater than one in a scope it believes is caught up knows unambiguously it missed something... and should issue a targeted resync."
On any channel with concurrent canvas activity, that heuristic fires constantly on ordinary, correct state, producing needless resync storms, or forces every client to special-case "gaps are normal here," quietly abandoning the missed-event detection the sequencing scheme exists to provide.

Resolution: give `channel_seq_counters` a composite key of `(channel_id, stream_type)` with one row and one independent counter per stream, or split it into `message_seq_counters` and `canvas_seq_counters`, matching the "its own scope" language literally.
Whichever is chosen, state explicitly whether message and canvas-op sequences share a numeric space or not, since `realtime-sync.md`'s gap-detection logic behaves correctly under only one of those two readings.

### 2. No account-identity model exists for a user who wants one login across multiple official-instance communities

Target: Section 1's framing, "the official service is therefore not one large multi-tenant database, it is a fleet of small single-community processes," against `BRIEF.md`'s Account Model section, which lists "Official hosted service: Standard account creation" as a model distinct from the self-hosted invite flow.

Weakness: owner decision 4 settles that one backend deployment is one community, and `database.md` correctly, faithfully applies that to the official instance: each community, official or self-hosted, runs its own server image with its own SQLite file and its own independent `users` table.
Nothing in the schema, or in `stack-decision.md`, provides any cross-deployment identity, directory, or federation layer.
That means an official-instance user account, as modeled, is scoped to exactly one community with no mechanism for the same login to exist on a second official community, self-hosted or otherwise.
"Standard account creation" on a company-run hosted service ordinarily implies a single portable identity a user can bring to many servers, the way Discord or Slack accounts work; this schema cannot offer that, only a fresh, siloed account per community even on the official service.

Failure mode: a user signs up for one official community, wants to join a second official community a friend runs, and discovers they must create an entirely separate account with its own password and identity keys, indistinguishable from onboarding onto an unrelated self-hosted server.
This is not a hypothetical edge case, it is the default expected behavior of "official hosted service" as most users will read that phrase, and nothing in `database.md`'s open questions flags the gap for an owner decision, even though `realtime-sync.md` independently flagged the closely related direct-message consequence of the same owner decision ("direct messages assume a shared home server, and nothing says so") as needing an explicit product decision rather than silent implementation.

Resolution: raise this explicitly as an open question requiring an owner decision, mirroring how `realtime-sync.md` handled its DM finding, rather than letting the fleet-of-processes framing quietly foreclose portable official accounts.
If per-community accounts are the accepted model even on the official instance, say so plainly in the schema section so nobody discovers the limitation downstream in the client or in app store copy.

## Major findings

### 3. The RBAC resolution order in Section 3 contradicts `security.md`'s stated invariant

Target: Section 3, "the channel's role-level overwrites applied in role `position` order," against `security.md`'s permission model, "per-channel role overrides, then per-member overrides, with deny winning."

Weakness: "applied in role position order" describes sequential application, where each subsequent role's overwrite can overwrite the previous one's bits.
Under that reading, if a lower-position role denies a permission and a higher-position role's channel overwrite allows it, the higher-position role's allow wins because it is applied last, not because deny is defined to always win.
That is a different, and looser, algorithm than "deny winning," which `security.md` treats as an unconditional property of the single evaluator function it calls out as needing to be "exhaustively tested."

Failure mode: a moderator stacks a restrictive role on a problem member expecting an absolute per-channel deny, but a different, higher-position role the same member also holds grants the same permission at the channel level, and the higher-position role's allow silently wins, an escalation path in exactly the function `security.md` singled out for exhaustive testing.

Resolution: state explicitly whether channel role-overwrites are combined by union across all of a member's roles with deny taking precedence across that whole union (matching `security.md`), or truly applied sequentially by position, and make the schema and the effective-permission function agree with whichever is chosen.

### 4. Owner decision 6's admin-issued one-time reset code has no schema representation anywhere

Target: the core schema block in Section 2, against owner decision 6, "self-hosted account recovery: admin-issued one-time reset code only for v1."

Weakness: `invites` gets a full table with a hashed code, issuer, use limits, and expiry.
The reset-code mechanism, an owner-mandated, already-accepted product decision with the same shape (a hashed one-time secret with an issuer and an expiry), has no equivalent table, column, or mention anywhere in the schema.

Failure mode: the mechanism the owner explicitly chose over recovery email has nowhere to store the code hash, which admin issued it, when it expires, or whether it has been redeemed, so it cannot be implemented from this schema without inventing the missing table from scratch during coding, the exact kind of foundational, hard-to-retrofit gap this report elsewhere argues should be caught before implementation.

Resolution: add a `password_reset_codes` table (or equivalent) with `user_id`, `code_hash`, `issued_by`, `issued_at`, `expires_at`, `used_at`, matching the rigor already given to `invites`.

### 5. Account-deletion tombstoning only specifies `messages.author_id`; every other foreign key into `users` is silent, and `groups.owner_id` is the dangerous one

Target: Section 6, "account deletion tombstones the `users` row... but authored messages are kept with the author shown as removed," against `groups.owner_id`, `invites.created_by`, `canvas_objects.created_by`, and `canvas_ops.actor_id`.

Weakness: the report works out the one foreign key most visible to the reader, messages, in detail, but says nothing about what happens to a group when its owner's account is tombstoned, nor about the other, lower-stakes references into `users`.
Unlike an author field on a message, `owner_id` on a group is not just an attribution label, it is very likely the seat that carries exclusive administrative capability such as deleting the community or reassigning roles that nothing else in the schema can grant.

Failure mode: a group's owner deletes their own account under the App Store-mandated deletion flow `appstore.md` requires, and the community they created has no path back to an owner, no defined transfer, and potentially no user left who can perform owner-only actions, since the RBAC model in Section 3 never establishes that any role short of ownership can substitute for it.

Resolution: define `ON DELETE` or application-level behavior for every foreign key into `users`, and specifically require an ownership-transfer step before a group owner's account deletion completes, or define an explicit orphaned-group policy (auto-transfer to the next-senior admin role, or archive-read-only) rather than leaving the state undefined.

### 6. Server-held attachment encryption has no key-management data model, and the backup plan does not say the key must live outside the file it protects

Target: Section 6, "content is encrypted at rest under a server-held key," and Section 7's `VACUUM INTO` backup of the SQLite database file.

Weakness: there is no column anywhere on `attachments` for a key id or key version, no mention of per-file nonce or IV storage, and no statement of where the server-held key itself is stored relative to the database file being backed up.
Without a key id or version column, rotating the key later, standard practice after any suspected compromise, has no way to tell old-key blobs from new-key blobs mid-migration, meaning rotation can only ever be an all-at-once, whole-corpus decrypt-and-reencrypt operation with no incremental path.
Separately, Section 7's backup plan describes backing up the database file with `VACUUM INTO` and attachment blobs separately by tarball, but never states that the encryption key must live outside both artifacts, so a careless implementation that stores the key in a config table inside the same SQLite file would ship the key inside every single backup, making "encrypted at rest" provide no protection against exactly the threat, a stolen backup, that it exists to defend against.

Failure mode: a future key rotation has no incremental path and becomes a risky big-bang migration, and if the key is ever colocated with the database file by an implementer with no guidance against it, every backup silently carries both the ciphertext and the key needed to read it.

Resolution: add a `key_version` column to `attachments`, document nonce or IV storage explicitly, and state plainly in the backup section that the server-held key must be stored and backed up separately from the database file and the attachment tarball.

### 7. Excluding reactions from the `seq` stream removes the only offline catch-up mechanism the sync design has for them

Target: Section 4, "reactions are deliberately left out of the seq stream... forcing them through the same total order would add write contention for no client-visible benefit," against `realtime-sync.md`'s catch-up sync, which works by "an indexed range scan on scope and sequence greater than the supplied cursor."

Weakness: the write-contention argument is real for live, connected clients, since reactions are small and idempotent and do not need strict ordering against messages while a session is live.
But `realtime-sync.md`'s entire offline catch-up mechanism is built around per-scope sequence cursors, and a table with no sequence has no cursor a reconnecting client can use to ask "what changed here since I was last online."
Nothing in either report describes an alternative path, such as re-sending full reaction state whenever the parent message is resynced, for a client to learn about reactions added or removed while it was offline.

Failure mode: a user goes offline for a day, reconnects, runs the documented catch-up sync, and has no documented way to learn that three reactions were added to a message they already have cached locally, since the table that changed carries no sequence for the sync protocol to query against.

Resolution: either give reactions their own lightweight per-channel sequence purely for catch-up purposes (not for live ordering), or explicitly document that reaction state is always refreshed as part of resyncing the parent message, and say which.

### 8. The R-Tree virtual table is presented as a simple index but is a separate shadow table needing explicit sync, with an undocumented integer-key constraint

Target: Section 6, "`canvas_objects` gets explicit `x, y, w, h` columns backed by a SQLite R-Tree virtual table."

Weakness: unlike a real SQLite index, an R-Tree virtual table is not automatically maintained by the engine; it is a second table the application must insert into, update, and delete from in step with every write to `canvas_objects`, exactly the kind of synchronization discipline this same document names explicitly for FTS5 ("kept in sync by insert and update triggers") but never mentions for the R-Tree table at all.
Separately, SQLite's R-Tree module requires its id column to hold plain 64-bit integers; `canvas_objects.id` is a UUID by the same identity convention used everywhere else in this schema, so the R-Tree table cannot use it directly and must instead be keyed off `canvas_objects`'s implicit rowid, which only exists if the table is not declared `WITHOUT ROWID`, an easy and reasonable-looking choice for a table with an explicit non-integer primary key that would silently make this whole design unimplementable if chosen.
`voice-canvas.md`'s own rendering section considered and explicitly rejected an R-tree for the closely related client-side viewport-culling problem, "a uniform grid spatial index... not an R-tree, favoring simplicity," without this document acknowledging or reconciling why the server-side answer differs.

Failure mode: a missed or buggy sync path between `canvas_objects` and its R-Tree shadow table produces objects that silently vanish from or incorrectly appear in viewport queries after a move or resize, the kind of drift bug that is invisible until a user reports an object that will not show up, and an implementer who reaches for `WITHOUT ROWID` on `canvas_objects` for its UUID primary key breaks the R-Tree integration entirely with no compiler or runtime error pointing at why.

Resolution: state the same trigger-based sync discipline for the R-Tree table as is already specified for FTS5, explicitly forbid `WITHOUT ROWID` on `canvas_objects` with a one-line comment explaining why, and briefly reconcile the divergence from `voice-canvas.md`'s client-side rejection of R-Tree, even if the answer is simply that SQLite ships it for free server-side while Flutter has no equivalent library.

### 9. The already-flagged "trivial" second permissions column understates its own blast radius

Target: Section 3's risk note, "a second column is a trivial additive migration if ever outgrown," against `stack-decision.md` Section 5's schema-first, code-generated wire format shared by Dart and Rust.

Weakness: because the wire protocol is generated from one schema of record for both the Flutter client and the Rust server, widening the permission representation is not a SQL `ALTER TABLE` plus a server recompile.
It is a coordinated change to the shared schema, regenerated Dart and Rust types, every permission-check call site on both ends including the client-side UX checks `security.md` describes, and a compatibility window where self-hosted servers on the old single-column format and clients expecting two columns, or the reverse, must both behave sensibly.

Failure mode: the risk is treated as "a rushed schema change under pressure," when the actual event is a cross-language, cross-repository flag day across every self-hosted server in the field at once, a materially larger and riskier operation than the report's own wording suggests.

Resolution: reword the risk to reflect the true scope, and consider reserving the second permissions column, or at least the wire-format field slot for it, from day one even if it is always zero, so the day it is needed is a data migration only, not a protocol migration too.

## Minor findings

### 10. `VACUUM INTO` defers WAL checkpointing for its full run, which can grow the WAL file during exactly the operation meant to protect a disk-constrained self-host

Target: Section 7, "SQLite's `VACUUM INTO` for an atomic hot backup under WAL mode, scheduled by cron."

Weakness: `VACUUM INTO` holds a read snapshot open for as long as the copy takes, and WAL checkpointing cannot fully reclaim the WAL file while any reader holds an old snapshot open, so a slow backup on a busy channel can let the WAL file grow substantially for the duration of the backup itself.

Failure mode: a self-host with tight disk headroom, the exact profile the brief targets, sees a disk-usage spike during its own backup job, worse the busier the channel and the slower the underlying disk, with nothing in the report flagging it as a thing to monitor.

Resolution: note this tradeoff explicitly and recommend scheduling backups during low-activity windows, or monitoring WAL file size as a backup-health signal.

### 11. FTS5 sync via "insert and update triggers" does not confirm soft deletes are excluded from search results

Target: Section 5, "kept in sync by insert and update triggers."

Weakness: messages are soft-deleted via `deleted_at`, per Section 4's retention model, not hard-deleted, so removing a deleted message from search results depends on the update trigger explicitly reacting to a `deleted_at` transition, not just to content edits.
The report never confirms this case is handled, only that update triggers exist in general.

Failure mode: a deleted message keeps surfacing in full-text search results indefinitely, since nothing states that the trigger logic treats a soft delete as a reason to remove the row from the FTS index.

Resolution: state explicitly that the update trigger removes a row from the FTS index when `deleted_at` transitions from null to non-null, not only when `content` changes.

### 12. `invites.role_grant` is a single scalar while the RBAC model it feeds is explicitly many-to-many

Target: Section 2's `invites(..., role_grant, ...)`, against `member_roles(group_id, user_id, role_id)` being an explicit many-to-many join table.

Weakness: every other part of the RBAC design in Section 3 supports a member holding several roles at once, but an invite can only grant exactly one role on redemption, an unexplained asymmetry.

Failure mode: an admin who wants a single invite link to grant two roles at once, for example both a base "member" role and a "beta-tester" role, cannot express that with this table and must instead manually add the second role after each redemption.

Resolution: either state this is an intentional v1 simplification, or change `role_grant` to a small join table so invites can grant more than one role.

### 13. The retention section's "lighter audit record" for canvas moderation history has no accompanying schema

Target: Section 7, "a lighter audit record of who created or removed which object is kept independently and longer," against the rest of the document, which pairs every other retention decision with a concrete table or column.

Weakness: this is stated as policy with nothing backing it in the schema, unlike the `deleted_at` columns, partial indexes, and dedicated tables given to every other retention decision in the document.

Failure mode: an implementer reaches this sentence with no guidance on what the audit record actually looks like, and has to design it from scratch, silently reintroducing exactly the compaction-versus-audit-trail tension this report is trying to resolve if the ad hoc design gets it wrong.

Resolution: add a minimal `canvas_audit_log` table (`channel_id`, `object_id`, `actor_id`, `action`, `created_at`) explicitly exempted from the 30-day compaction window, so the policy has a schema to point at.

## Closing note

The schema in this pass is substantially stronger than a naive rebuild: multi-role RBAC, keyset pagination, the sha256-first attachment dedup order, and the account-deletion tombstone story are all real, well-reasoned answers to problems a fresh design has to solve.
The findings above cluster around two patterns worth naming directly.
First, two places where the document's own prose promises more than its own schema delivers in the same section: the two-scope claim in Section 4 that one counters table cannot satisfy, and the FTS5-grade sync discipline named for search but not extended to the R-Tree table doing the analogous job for canvas.
Second, several owner-mandated or App-Store-mandated commitments that have rationale and precedent elsewhere in the document but no schema of their own: the reset-code mechanism, attachment key rotation, and account-deletion's effect on group ownership.
Both patterns are the same kind of gap this report itself is good at catching elsewhere, just not turned on every section evenly.

## Open questions the specialist should have raised but did not

- Do `messages` and `canvas_ops` share one interleaved per-channel sequence space or two independent ones, and does `channel_seq_counters` need a second key column either way (see finding 1)?
- Should the official instance offer one portable account across multiple official communities, and if so what identity layer sits above the per-deployment `users` table (see finding 2)?
- Does channel role-overwrite resolution truly apply sequentially by role position, or does deny unconditionally win across the union of a member's roles as `security.md` states (see finding 3)?
- Where does the admin-issued one-time reset code from owner decision 6 actually live in the schema (see finding 4)?
- What happens to a group when its owner's account is deleted, and is an ownership-transfer step required before deletion completes (see finding 5)?
- How is the server-held attachment encryption key rotated, and is it guaranteed to be stored and backed up separately from the database file it protects (see finding 6)?
- How does a client discover reactions added or removed while it was offline, given reactions carry no sequence for catch-up sync to query against (see finding 7)?
