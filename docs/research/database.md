# Database and Storage Layer

Status: pre-implementation research.
Scope: storage engine choice for the official and self-hosted instances, core schema, indexing and pagination for message history, full-text search, migration tooling, retention, and backup.
Assumes the stack already committed in `backend.md` (Rust, Axum, SQLx, PostgreSQL), and reconciles with `voice-canvas.md`, `realtime-sync.md`, and `security.md` where their decisions touch storage.
Divergences from a sibling report are called out, not silently overridden.

## 1. Storage engine: Postgres only, for every deployment size

Verdict: PostgreSQL is the single storage engine for the official instance and every self-hosted instance, with no SQLite option and no dual-backend abstraction layer.
The push relay keeps its own separate SQLite store, as `backend.md` already decided.
That is a different, simpler data shape and is not affected by this verdict.

Rationale: the schema below needs row-level locking for concurrent canvas and message writes, JSONB with GIN indexing, generated tsvector columns, and partial indexes.
SQLite has none of these in a form strong enough for this workload.
Its write model serializes at the database or `BEGIN IMMEDIATE` transaction level, not per row, so a lively voice-canvas session with several people drawing at once would serialize onto one lock even on spare hardware.
That is a correctness and latency risk, not just a scale risk, and it hits exactly the self-hosted "handful of users" case the brief cares about, since a small friend-group call is still a bursty multi-writer workload.

Alternatives rejected:

- **SQLite-first, Postgres for the official instance only.** Rejected because it means designing two concurrency models and shipping the weaker one to every self-hoster, the deployment the brief wants to be lightweight and pleasant, not the one where correctness matters less.
- **One SQL abstraction targeting both engines.** Rejected because SQLx's compile-time query verification, one of the stated reasons for choosing Rust, checks queries against one real schema at build time.
Supporting two engines means two parallel query implementations forever, or dropping to a dynamic query builder that gives up the safety that motivated the choice.
It would also force the schema down to the weaker engine's feature set, against the brief's "future scalability" goal.

Risk: a from-scratch self-host needs two containers instead of one embedded file, and a real DBMS to back up.
Mitigated by a `postgresql.conf` tuned for a tiny instance in the example compose (`backend.md` targets under 80 MB idle Postgres at this scale), and a single `docker-compose up` onboarding path.

## 2. Core schema

The entity list in this assignment omits a `devices` table, but `backend.md` already commits to per-device refresh tokens and `security.md` to a device session record.
Both need somewhere to live, so a `devices` table is added here rather than silently left out.
An instance, official or self-hosted, can host more than one group, the same way one Discord deployment hosts many guilds.
DMs are channels with no group, gated by a membership join table instead of role permissions.

```
users(id, username, display_name, password_hash, public_identity_key, created_at)
devices(id, user_id, platform, push_token_ref, last_seen_at, revoked_at)
groups(id, name, owner_id, created_at)
group_members(group_id, user_id, role, joined_at)           pk(group_id, user_id)
channels(id, group_id nullable, kind, name, position, created_at)
dm_participants(channel_id, user_id)                        pk(channel_id, user_id)
messages(id, channel_id, author_id, content, content_tsv,
         is_encrypted, reply_to_id, created_at, edited_at, deleted_at)
attachments(id, sha256, size_bytes, mime, storage_key, encrypted, created_at)
message_attachments(message_id, attachment_id, position)    pk(message_id, attachment_id)
read_states(user_id, channel_id, last_read_message_id, updated_at)  pk(user_id, channel_id)
invites(id, group_id, code_hash, created_by, max_uses, use_count, role_grant, expires_at, revoked_at)
canvas_objects(id, channel_id, kind, z_index, transform, props, from_user_id, created_at, updated_at, deleted_at)
canvas_ops(id, channel_id, actor_user_id, op_type, object_id, patch, created_at)
```

A few choices reuse or reconcile sibling reports rather than reinvent them.
Message content is server-visible plaintext with an `is_encrypted` escape hatch, matching `security.md`'s verdict that v1 is transport-encrypted only, with end-to-end DMs deferred and pre-wired, not shipped.
Attachments are content-addressed by `sha256` for dedup and encrypted at rest under a server key before the hash is stored, matching `security.md`.
The database stores only metadata and a storage key, never blob bytes, keeping table and backup size small.
`canvas_objects` and `canvas_ops` reuse `voice-canvas.md`'s materialized-state-plus-op-log split unchanged, except that `id` supersedes that report's separate per-channel `seq` counter, for the reason given next.
Invites store a hashed code, never plaintext, matching `security.md`.

## 3. Ordering, indexing, and pagination for message history

Verdict: every persisted row, across messages, canvas ops, and any future event type, uses one global 64-bit snowflake `id` as both primary key and total-order key, adopting `realtime-sync.md`'s ID scheme rather than proposing a second one.
This is a deliberate reconciliation.
`voice-canvas.md` proposed a per-channel `seq bigint` assigned via `SELECT ... FOR UPDATE`, the same lock-then-append pattern that caused echo-messenger's TOCTOU bug, because every write still contends on one counter row per channel.
A snowflake ID is generated in-process with no database round trip and no shared counter, so concurrent writes to the same channel no longer serialize on ID allocation, only on the row insert itself, which Postgres already handles well.

Message history pagination is keyset-based, cursor on `id`, never `OFFSET`/`LIMIT`: `WHERE channel_id = $1 AND id < $cursor ORDER BY id DESC LIMIT 50`.
Offset pagination is rejected: its cost grows with depth, and its results visibly shift under concurrent inserts, a real defect in a live chat log.
The supporting index is `(channel_id, id DESC)`, partial on `deleted_at IS NULL` so soft-deleted rows never enter the hot scan path, and it serves `realtime-sync.md`'s unread count directly, so `read_states` needs no index beyond its primary key.
Canvas ops use the identical index shape.
`canvas_objects`, the mutable materialized table, keeps `voice-canvas.md`'s viewport-first pagination for live rendering, with `id` only as a stable tiebreaker.

## 4. Full-text search

Verdict: server-side Postgres full-text search, a generated `tsvector` column on `messages.content` with a GIN index, partial on `is_encrypted = false`.
This is a clean call, not an open question, because `security.md` resolves the brief's ambiguous "lightweight encryption" phrase to transport-only for v1, so the server holds plaintext and indexing it server-side is legitimate today.
The partial index means that once opt-in E2EE DMs ship, per `security.md`'s pre-wiring, those rows are simply never indexed, no migration needed; encrypted search becomes a client-side concern at that point, most naturally Drift's own SQLite FTS5.
Rejected: Elasticsearch or Meilisearch, correct at large scale but a second heavyweight service that fails the "extremely lightweight" self-hosted bar for something Postgres already does well here.
Also rejected: client-side search as the v1 default even for plaintext content, forgoing cheap indexed server-side search for no benefit while nothing is actually encrypted yet.
Risk: GIN indexes add write cost per insert; the generated column computes once at write time, not query time, but insert latency is worth measuring once volume is realistic.

## 5. Migration tooling

Verdict: `sqlx migrate`, versioned forward-only `.sql` files embedded in the binary and auto-applied at startup, matching echo-messenger's proven pattern.
Rejected: a second tool such as `refinery` or `sea-orm-migration`, duplicating what SQLx already provides.
Also rejected: down-migrations as the primary rollback path, since a fleet of independently operated self-hosts cannot roll back in lockstep; a bad migration is fixed forward instead.
Every migration is hand-written and reviewed, not generated, since the schema leans on Postgres-specific features generators frequently get wrong.
Risk: a bad forward-only migration ships before it is caught, mitigated by running the full suite against a real ephemeral Postgres in CI, already part of `backend.md`'s testing strategy.

## 6. Retention

Messages default to keep-forever, matching Discord and Slack scrollback expectations, with soft delete via `deleted_at` filtered at query time, echo-messenger's proven pattern.
Group and channel admins get an explicit, off-by-default disappearing-messages toggle, per the brief's admin goals; a background sweep hard-deletes rows past TTL on a schedule, not inline on every read.
Attachments are swept by an orphan job removing blobs with no remaining `message_attachments` reference.
Canvas op-log retention follows `voice-canvas.md`'s guidance unchanged: raw ops older than roughly thirty days may be compacted once no client needs to replay from an arbitrary point, a v1.x job, not a launch blocker.

## 7. Backup strategy

Official instance: continuous WAL archiving plus periodic `pg_basebackup` for point-in-time recovery, with scheduled restore drills, since an untested backup is not a backup.
Self-hosted instance: a documented, scripted `pg_dump` plus attachment-directory tarball on a cron, reusing echo-messenger's grandfather retention (seven daily, four weekly, six monthly).
Shipped as an optional compose service, not a mandatory sidecar, so a tiny instance is not forced to run it, but documented strongly enough that skipping it is a deliberate choice.
A periodic automated restore-and-checksum job is recommended for both tiers, worth flagging explicitly since most self-hosted setups skip backup verification and a backup nobody has restored is a false sense of safety.

## Open questions

- Whether the official instance needs more than one application-server process for v1: if so, snowflake ID generation needs an assigned node-id range per process, a small addition, decided before launch, not retrofitted.
- Default attachment storage backend for self-hosters, local disk versus an S3-compatible target: jointly a database and deployment-infrastructure decision, left to whichever report owns deployment defaults.
- Default disappearing-message and canvas-op-log retention windows are product policy, not technical, and are deliberately left open, matching `voice-canvas.md`'s own framing of the same question.
