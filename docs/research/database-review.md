# Database Plan: Adversarial Review

Target document: `docs/research/database.md`.
Cross-checked against `docs/BRIEF.md` and the sibling reports in `docs/research/` (`security.md`, `backend.md`, `realtime-sync.md`, `voice-canvas.md`, `flutter-client.md`, `performance.md`, `appstore.md`, `devops.md`, `media.md`).

Severity key: critical findings would force a redesign of the plan as written.
Major findings are real defects that should block sign-off until addressed.
Minor findings are worth fixing but do not block the overall direction.

## Critical findings

### 1. The permission model `security.md` designed cannot be represented by this schema

Target: Section 2's core schema, specifically `group_members(group_id, user_id, role, joined_at)` and `invites(..., role_grant, ...)`.

Weakness: `security.md`'s permission model section is explicit about the shape it needs: "@everyone base, then the union of member roles, then per-channel role overrides, then per-member overrides, with deny winning and ADMINISTRATOR bypassing all checks."
That sentence alone requires four things the schema does not have: a `roles` table (group-scoped, named, each carrying its own permission bitfield), a many-to-many member-to-role assignment ("union of member roles" is plural by design, one member can hold several roles at once), a per-channel role-override table, and a per-member override table.
`database.md`'s `group_members` table instead stores a single scalar `role` column per member, one role, not a union of several, and there is no channel-scoped or member-scoped override table anywhere in the schema.
`invites.role_grant` is likewise singular, consistent with the same one-role-per-member assumption, not with the multi-role model `security.md` actually designed.

Failure mode: implemented literally, every permission check in the system, viewing, sending, managing messages, kicking, banning, canvas-edit, everything `security.md`'s flag list defines, has nowhere to read a per-channel or per-member override from, and no member can ever hold more than one role.
A guild owner who wants a "moderator" role and a separate "voice-only" role stacked on the same person, ordinary Discord-parity behavior the brief explicitly asks for, cannot be modeled.

Resolution: add `roles`, `member_roles`, `channel_role_overrides`, and `channel_member_overrides` tables (or an equivalent normalized shape) to the core schema section, and update `group_members` to drop the single `role` column in favor of the join table.
This is exactly the kind of foundational, hard-to-retrofit choice `database.md` itself argues for getting right on day one elsewhere in the report; the permission model deserves the same treatment.

### 2. The case against SQLite conflates a locking-model difference with the specific bug it invokes, and is not quantified against the brief's own scale target

Target: Section 1's verdict and rationale, "PostgreSQL is the single storage engine... with no SQLite option."

Weakness: the stated rationale is that SQLite's write model "serializes at the database or `BEGIN IMMEDIATE` transaction level, not per row," and calls this "a correctness and latency risk, not just a scale risk," explicitly invoking echo-messenger's canvas TOCTOU bug as the failure this is meant to prevent.
But the TOCTOU bug cited elsewhere in this same report (Section 3) and independently in `realtime-sync.md` was an application-level bug: a shared per-channel counter row that concurrent writers had to `SELECT ... FOR UPDATE` and increment, racing on that specific lock-then-append pattern.
A single-writer, whole-database lock, which is what SQLite actually provides, cannot produce that class of bug; it enforces a strict global write order, which is the opposite of a race condition, not a milder version of one.
What SQLite's coarser locking actually costs is throughput and latency under concurrent write load, a real and fair concern, but a different one than "correctness," and the report never quantifies it: no benchmark, no rows-per-second figure, no comparison against the brief's own stated self-host scale ("a handful of active users").
SQLite in WAL mode routinely sustains thousands of small writes per second on ordinary disks; the canvas op rate this report is worried about (`realtime-sync.md`'s own limit is 20 ops/second/user) is well inside that range for a "handful of users" session.

Failure mode: this is the single largest cost the report imposes on every self-hoster, an admitted second stateful container instead of one embedded file, a real DBMS to patch, upgrade across major versions, and back up, for the exact deployment profile the brief says should "remain extremely lightweight" and where the Database section explicitly asks to "avoid premature complexity."
If the underlying premise turns out wrong once actually measured, correcting it later means retrofitting a second storage backend after every query has been written against SQLx's single-schema compile-time checking, the exact dual-maintenance burden this same section argues is unacceptable.

Resolution: before treating this as settled, run the actual benchmark: concurrent canvas writers against SQLite WAL mode at the brief's own stated scale, and report real p99 write latency, not an assumption.
If Postgres is still the right call once measured, restate the rationale in terms of the real cost (operational and maintenance burden of a second stateful service) rather than a correctness claim the cited bug does not actually support.

### 3. Account deletion, a mandatory App Store requirement, has no data-model story

Target: the `users` table and every table with a foreign key into it (`messages.author_id`, `groups.owner_id`, `attachments`, `group_members`, `devices`), against `appstore.md`'s verdict.

Weakness: `appstore.md` is unambiguous: "if your app supports account creation, you must also offer account deletion within the app... promote account deletion from an implementation detail to a mandatory verb in the wire protocol itself, implemented in the reference server from day one."
`database.md` never mentions account deletion, a tombstone or anonymization mechanism, or `ON DELETE` behavior for any foreign key into `users`, even though the retention section covers message, attachment, and canvas-op deletion in some detail.
Messages default to keep-forever per this same report's own retention verdict, which means a deleted user's message history is expected to persist for everyone else in a shared channel, the same "deleted user" placeholder pattern Discord and Slack use, but nothing in the schema supports it: there is no way to sever a `users` row from its personal data (`password_hash`, `public_identity_key`) while preserving the messages, group ownership, and attachments other users still depend on.

Failure mode: implemented literally, either account deletion cascades and silently destroys other members' shared conversation history and any group the deleted user owned, a real data-loss bug triggered by a single user exercising a right Apple requires the app to offer, or deletion is blocked entirely by foreign key constraints and the feature does not actually work, an App Store rejection risk for the platform the brief names as the primary initial testing target.

Resolution: add an anonymization path to the `users` table (a `deleted_at` flag, cleared PII columns, a placeholder display name) rather than a hard delete, define `ON DELETE` behavior explicitly for every foreign key into `users`, and decide what happens to `groups.owner_id` when an owner deletes their account (transfer, orphan-and-archive, or block deletion behind a required ownership-transfer step).

## Major findings

### 4. The `devices` table does not store what `backend.md` and `security.md` actually need it to

Target: `devices(id, user_id, platform, push_token_ref, last_seen_at, revoked_at)`, added specifically "since the backend and security reports already commit to per-device refresh tokens and device session records."

Weakness: `security.md`'s actual device session record is "device id, platform, name, last-seen, push registration, identity key," and separately describes refresh-token rotation with reuse detection, "a replayed old token revokes the whole family," which requires storing a token hash and a token-family identifier somewhere.
The `devices` table as specified has none of this: no `name` column for the in-app device list the brief's admin section and `security.md` both call for, no refresh-token hash, and no family identifier for reuse detection.
Adding this table was the right instinct, closing a real gap the entity list left out, but the columns chosen only cover push-routing metadata, not the session and revocation state the sibling reports actually need a home for.

Failure mode: a device is revoked from the admin device list, but with nowhere to store a token hash or family id, there is no schema-level way to actually invalidate that device's refresh token family, the exact "instant revocation" property `security.md` chose opaque tokens specifically to get.

Resolution: add a `sessions` or `refresh_tokens` table (`token_hash`, `device_id`, `family_id`, `issued_at`, `rotated_at`, `revoked_at`) alongside `devices`, and add a `name` column to `devices` for the in-app device list.

### 5. Content-addressed attachment dedup has no uniqueness guarantee and no path for future encrypted attachments

Target: `attachments(id, sha256, size_bytes, mime, storage_key, encrypted, created_at)`.

Weakness: dedup by content hash only works if a lookup-before-write happens under a uniqueness guarantee; nothing in the schema states a unique constraint on `sha256`, so two concurrent uploads of the same file (a popular GIF pasted by five people during one canvas session) can race past a check-then-insert and create duplicate stored blobs, silently defeating the dedup rationale the report gives for this design.
Separately, the report's own description of the write path, "encrypted at rest under a server key before the hash is stored," does not say whether the hash is computed before or after encryption, and the two orders produce opposite outcomes: hashing plaintext preserves dedup but requires the server to see plaintext, while hashing ciphertext with a properly random IV makes every upload of identical content look unique and breaks dedup entirely.
Unlike `messages.is_encrypted`, `attachments` has no per-row flag distinguishing content that must stay server-visible from content that has opted into future E2EE, so when opt-in E2EE DMs eventually ship, attachments in those conversations have no schema-level way to be excluded from the plaintext-hashing dedup path the rest of the design depends on.

Failure mode: storage grows unboundedly duplicated under concurrent upload load, undermining the stated goal of keeping "table and backup size small," and attachments become a permanent server-visible exception once E2EE DMs ship, an undisclosed privacy gap of exactly the kind `voice-canvas-review.md` already flagged for canvas content.

Resolution: add a unique constraint on `sha256`, specify hash-before-encrypt explicitly, and add an `is_encrypted` or `e2e_pending` column to `attachments` mirroring the one on `messages`.

### 6. `realtime-sync.md`'s own sync protocol names a synced kind this schema never defines

Target: the core schema in Section 2, against `realtime-sync.md`'s catch-up endpoint, `GET /api/sync?after=<last_id>&kinds=message,reaction,canvas_op&limit=500`.

Weakness: `reaction` is listed as a first-class synced event kind in the sibling report this document explicitly reconciles with elsewhere, but no `reactions` table, or any reaction-related column, appears anywhere in `database.md`'s schema.
This is a base Discord-parity feature the brief asks for ("replicate the base level functionality of Discord"), and the report's own stated methodology is to catch exactly this kind of cross-report gap, as demonstrated by the `devices` table addition in the same section.

Failure mode: implementers reach the sync protocol section, find `kinds=message,reaction,canvas_op` already assumed, and have to reverse-engineer a reactions table's shape (`message_id`, `user_id`, `emoji`, an ordering id) with no design guidance on indexing, ordering, or how it participates in the same global snowflake id space every other persisted row uses.

Resolution: add a `reactions` table to the core schema section with the same id-as-ordering-key treatment given to every other row.

### 7. The global snowflake id's cross-table ordering guarantee is not safe during a rolling deploy, a transient risk distinct from the steady-state multi-process question already flagged as open

Target: Section 3's verdict, "one global 64-bit snowflake id as both primary key and total-order key," against `realtime-sync.md`'s assumption that "each server process is the sole writer for its own database, so no worker/datacenter coordination bits are needed."

Weakness: the open questions section flags multi-process node-id assignment as a future concern only if "the official instance needs more than one application-server process for v1," framing it as a steady-state scaling decision.
That framing misses a narrower, transient version of the same risk: `devops.md`'s own open questions raise "watchtower-style auto-update from `:latest`" as a live candidate deployment model for the official instance, and any standard zero-downtime rolling update (start a new instance, health-check it, then stop the old one) runs two processes with independent in-process id counters concurrently for the overlap window, by design, not by misconfiguration.
A plain single-container self-hosted `docker compose up -d` recreate is sequential and not at risk by default, but the official instance, or any self-hoster running a load-balanced or orchestrated setup (Kubernetes, Swarm, Nomad), is exactly the case this report should have covered and did not.
Because the ordering guarantee this scheme provides is explicitly cross-table (the unified sync cursor merges message, reaction, and canvas_op by id across different tables), a collision during that window is not caught by any single table's own primary-key uniqueness constraint, since the colliding rows can live in two different tables entirely.

Failure mode: two events, say a message and a canvas op, generated by the outgoing and incoming process within the same overlap window, get the same id value; the unified sync cursor's total-order contract silently breaks for any client whose catch-up page happens to span that id, with no error raised anywhere, since the id constraint is per-table, not global.

Resolution: reserve at least one bit for a coarse instance/generation identifier even in the default single-process design, or require an explicit startup handshake ensuring only one process mints ids at a time before any rolling-update deployment model is adopted for the official instance.

### 8. Auto-applied forward migrations at startup have no zero-downtime story for the official instance

Target: Section 5's verdict, "`sqlx migrate`, versioned forward-only `.sql` files... auto-applied at startup," against the official instance's real production traffic and `devops.md`'s deploy model.

Weakness: for a self-hosted instance with a handful of users and small tables, blocking startup on a migration is harmless.
For the official instance, which the brief and `devops.md` both treat as a real, continuously-running production deployment, a migration that adds a `NOT NULL` column, builds a non-concurrent index, or rewrites a large `messages` table can run long enough to fail a container health check.
Nothing in the migration section discusses `CREATE INDEX CONCURRENTLY`, multi-step backward-compatible column additions, or what happens when an orchestrator kills a container mid-migration because it missed its readiness window.

Failure mode: a routine schema change on the official instance gets killed mid-migration by the deploy tooling, leaving the schema in a partially applied state with no documented recovery procedure, turning a planned deploy into an incident.

Resolution: document a zero-downtime migration discipline for the official instance specifically (concurrent index builds, additive-then-backfill-then-constrain column changes), even if the self-hosted default keeps the simpler auto-apply-at-startup model.

### 9. The server schema and the client's independent Drift schema are never reconciled

Target: `database.md`'s silence on `flutter-client.md`'s decision, "Drift (SQLite) as the single source of truth for conversations, messages, channels, and canvas cache," with its own codegen pipeline.

Weakness: the brief lists "fast synchronization" and "future scalability" as explicit database goals, and `database.md` positions itself as the report that owns schema and sync-supporting indexing, but it never once discusses how a server-side schema change (a new column, a new table like the missing `reactions` table above) propagates to the client's independently versioned Drift schema, or how a fleet of self-hosted servers running different schema versions against one official client release stays compatible.

Failure mode: a self-hoster runs an older server version against a newer official client release, or the reverse, a common self-host reality this project explicitly supports, and there is no documented mechanism, schema version negotiation, capability flags, or otherwise, for the client to know which columns or tables it can rely on.

Resolution: add a short cross-reference between `database.md` and `flutter-client.md` specifying how protocol or schema versioning is communicated to the client, even if the detailed design belongs to a different report.

## Minor findings

### 10. Small-instance Postgres tuning is not reconciled with the write-heavy tables the schema itself creates

Target: the `postgresql.conf` tuned for under 80MB idle (Section 1's risk mitigation), against `read_states` (updated on every read-state change) and `canvas_ops` (frequent small inserts plus periodic compaction).

Weakness: aggressive small-instance tuning typically reduces autovacuum workers and frequency alongside `shared_buffers`, but `read_states` rows get updated, not inserted, on every read-state change, and `canvas_ops` both inserts constantly and later deletes in bulk during 30-day compaction, both classic bloat sources that need active autovacuum to control, a tension the report never mentions.

Failure mode: a small self-hosted instance's Postgres slowly bloats on these two tables over months of use, and the "under 80MB idle" figure quietly stops holding as dead tuples accumulate, discovered only once someone measures disk use, not flagged anywhere as a risk today.

Resolution: state autovacuum settings explicitly in the tuned config rather than leaving them as a side effect of the memory-focused tuning pass.

### 11. GIN write-cost risk is flagged but never checked against the project's own latency budget

Target: Section 4's risk note, "GIN indexes add write cost per insert... worth measuring once message volume is realistic," against `performance.md`'s "p99 server-side processing time... under 5ms at small scale" for the same write path.

Weakness: two reports set a number and a risk for the identical operation (persisting a message) without cross-referencing each other; it is not stated whether the 5ms budget already accounts for the generated `tsvector` and GIN maintenance cost, or whether that cost is expected to come out of headroom nobody has confirmed exists.

Failure mode: the 5ms budget gets adopted as a CI regression gate before anyone validates it against real GIN write cost, and the first load test either fails a gate that was never realistic or passes only because FTS was accidentally excluded from the measured path.

Resolution: have `performance.md`'s benchmark suite explicitly include the FTS write path, and have `database.md` reference the resulting number instead of restating an independent "worth measuring" note.

### 12. Full-text search uses a single, unstated language configuration

Target: the generated `tsvector` column implied in Section 4; no text search configuration is named beyond the implicit default.

Weakness: `to_tsvector` requires a language configuration for stemming and tokenization; an unstated default typically resolves to English, which degrades relevance for non-English content in a project with no stated restriction to English-speaking self-hosters.

Failure mode: a self-hosted instance used primarily in another language gets poor search relevance with no indication why, since the indexing choice was never surfaced as a decision.

Resolution: state the FTS language configuration explicitly, either a language-agnostic default (`simple`) or a per-message language field, and note it as a deliberate v1 limitation if English-only stemming is kept.

### 13. Self-hosted backup snapshot coordination is unstated

Target: Section 7's self-hosted backup script, "scripted `pg_dump` plus attachment-directory tarball on a cron."

Weakness: the two artifacts are captured independently with no stated ordering or locking between them; content-addressed, immutable attachments make this low-risk in practice, but the report does not say so, leaving a reader to wonder whether a restore could reference attachments the tarball does not yet contain.

Failure mode: minor in practice given content-addressing, but worth one sentence in the report rather than leaving it implicit.

Resolution: state explicitly that the ordering is safe because attachments are immutable and content-addressed, so a slightly stale tarball only means a not-yet-backed-up attachment, never a corrupted one.

### 14. Canvas op-log compaction conflicts with the same log's role as a moderation audit trail

Target: Section 6, "raw ops older than roughly thirty days may be compacted," against `voice-canvas.md`'s framing of the same log as the source for "who drew what, when," the moderation audit trail the brief asks for.

Weakness: a report filed more than a month after an incident, an entirely plausible delay for harassment or abuse reports, loses its evidentiary trail once compaction runs, and there is no flag in the design distinguishing "nothing happened in this range" from "this range was compacted," so the gap is invisible to whoever investigates later.

Failure mode: a moderator investigating a stale report finds an empty canvas history and cannot tell whether that means innocence or lost evidence.

Resolution: either exempt op-log rows tied to an open or recent moderation report from compaction, or explicitly document the audit-trail limitation created by the 30-day window so moderators know its boundaries.

## Closing note

Most of these findings share one root cause.
This report did the hard work of reconciling with `realtime-sync.md` and `voice-canvas.md` on ordering, and says so explicitly, but the same discipline was not applied evenly to `security.md`'s permission model, `appstore.md`'s account-deletion requirement, or `flutter-client.md`'s independent schema, three sibling documents whose decisions land directly on the tables this report owns.
The schema section's own stated methodology, "divergences from a sibling report are called out, not silently overridden," is the right standard.
The permission model and account deletion gaps are not divergences that were called out; they are commitments from sibling reports this schema does not yet support at all.

## Open questions the specialist should have raised but did not

- How does the schema represent `security.md`'s per-channel and per-member permission overrides, and multi-role membership (see finding 1)?
- What data is actually retained, transferred, or anonymized when a user exercises the mandatory account-deletion right, and what happens to groups they own (see finding 3)?
- Where do refresh-token hashes and reuse-detection family state actually live, given the `devices` table as specified does not hold them (see finding 4)?
- Is the `sha256` dedup hash computed before or after at-rest encryption, and how does dedup interact with attachments in a future end-to-end-encrypted conversation (see finding 5)?
- How does a client know which server-side schema version or capabilities it is talking to, given the server and client schemas evolve independently (see finding 9)?
