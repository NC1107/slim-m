# Database and Storage Layer

Status: pre-implementation research, fresh pass.
Scope: schema for users, devices, sessions and refresh tokens, RBAC, groups, channels, messages, reactions, attachments, invites, and canvas objects, plus indexing, keyset pagination, full-text search, forward-only migrations, retention, and backup.
Builds on the already-decided stack: Rust, Axum, Tokio, SQLite in WAL mode via sqlx, a single serialized writer path with a read-only pool, and UUIDv7 identity paired with a per-scope monotonic i64 sequence.

## 1. Engine role: SQLite for the official instance and every self-host, one tier

SQLite is not a concession for tiny self-hosts, it is right for the official instance too, because the owner decisions already establish that one backend deployment is one community.
The official service is therefore not one large multi-tenant database, it is a fleet of small single-community processes, each with its own SQLite file.
That is exactly the shape SQLite is strong at: perfect tenant isolation, no noisy-neighbor contention between communities, and a backup or migration of one community never touches another.
The usual objection to SQLite, that a busy multi-writer workload serializes on one file lock, does not apply here, because the architecture already funnels every write for a given process through one serialized writer task before it reaches the database.
SQLite's single-writer model is not a new constraint the database imposes on the app, it is the same constraint the app's own write path already chose, so the two line up instead of fighting each other.
Reads, including message history scans and canvas viewport queries, go through the separate read-only pool that WAL mode supports concurrently with the writer.
Escape hatch: the repository trait already required by the stack decision makes a future move to Postgres possible for a single community that genuinely outgrows one process, without a schema rewrite for everyone else.
Risk to flag now, not later: FTS5 and the R-Tree module used below are optional SQLite compile-time features, so the build must explicitly enable them in the sqlx/libsqlite3-sys feature flags, or search and canvas indexing silently degrade to table scans.

## 2. Core schema

```
users(id, username, display_name, password_hash, deleted_at, created_at)
devices(id, user_id, platform, identity_pubkey, push_registration_id, created_at, last_seen_at, revoked_at)
refresh_tokens(id, device_id, token_hash, family_id, issued_at, expires_at, revoked_at, replaced_by)
groups(id, name, owner_id, created_at)
roles(id, group_id, name, color, position, permissions, is_default, created_at)
group_members(group_id, user_id, nickname, joined_at)          pk(group_id, user_id)
member_roles(group_id, user_id, role_id)                       pk(group_id, user_id, role_id)
channels(id, group_id nullable, kind, name, position, created_at, archived_at)
channel_overwrites(channel_id, subject_type, subject_id, allow, deny)   pk(channel_id, subject_type, subject_id)
channel_members(channel_id, user_id, joined_at)                 pk(channel_id, user_id)   -- DMs and group DMs
messages(event_id, channel_id, seq, author_id, device_id, content, is_encrypted, reply_to_id, created_at, edited_at, deleted_at)
reactions(message_id, user_id, emoji, created_at)                pk(message_id, user_id, emoji)
attachments(sha256, size_bytes, mime, storage_key, encrypted, created_at)   pk(sha256)
message_attachments(message_id, attachment_id, position)         pk(message_id, attachment_id)
read_states(user_id, channel_id, last_read_seq, updated_at)      pk(user_id, channel_id)
invites(id, group_id, code_hash, created_by, role_grant, max_uses, use_count, expires_at, revoked_at)
canvas_objects(id, channel_id, kind, x, y, w, h, z_index, transform, props, created_by, created_at, updated_at, deleted_at)
canvas_ops(event_id, channel_id, seq, actor_id, op_type, object_id, patch, created_at)
channel_seq_counters(channel_id, next_seq)
```

There is deliberately no email column anywhere in v1, matching the no-email invite model for self-hosts and the admin-issued reset code decision for recovery, which needs no address to send anything to.
The official instance uses the same schema, so it does not collect an email address either unless a later, separate decision adds a nullable column through a forward-only migration.

## 3. RBAC with per-channel and per-member overrides

`roles.permissions` is a single 63-bit bitmask in a SQLite INTEGER, chosen over a wider bitset because a typical permission list fits comfortably under 63 flags, and adding a second column later is a trivial additive migration, so there is no reason to pay for headroom today.
A member's effective permission set is the union of their assigned roles' base bits, then the channel's role-level overwrites applied in role `position` order, then the channel's member-level overwrite applied last and absolute.
`channel_overwrites` is one polymorphic table keyed on `(channel_id, subject_type, subject_id)` rather than two near-identical tables, because the allow/deny resolution logic is identical for both subject kinds and a single table keeps that logic in one place.

## 4. Event identity, ordering, and keyset pagination

Every ordered stream (a channel's messages, a channel's canvas ops) is its own scope, with `seq` assigned from `channel_seq_counters` inside the same transaction as the insert.
Because only one writer task ever touches the database, that increment-then-insert is not a race the way a multi-writer `SELECT ... FOR UPDATE` counter would be, it is ordinary sequential code, which removes an entire class of bug rather than papering over it.
History pagination is keyset-based on `(channel_id, seq)`, never offset-based, since offset cost grows with scroll depth and its results shift under concurrent inserts.
The supporting index is `(channel_id, seq DESC)`, partial on `deleted_at IS NULL`, and it also backs `read_states.last_read_seq` unread counts without a second index.
Reactions are deliberately left out of the seq stream, they are small, commutative, idempotent set operations on `(message_id, user_id, emoji)`, and forcing them through the same total order would add write contention for no client-visible benefit.

## 5. Full-text search

SQLite FTS5 in external-content mode over `messages.content`, kept in sync by insert and update triggers rather than a generated column, since SQLite has no native tsvector equivalent.
The trigger only indexes rows where `is_encrypted = 0`, so once opt-in E2EE DMs ship, per the transport-only v1 stance, those rows simply stop entering the index, with no migration required.
The `unicode61` tokenizer is used for a dependency-free, good-enough default.
It has no real stemming, an accepted v1 limitation, not an oversight.

## 6. Attachments, canvas objects, deletion, and multi-device

Attachments are keyed by `sha256` as the primary key, giving instance-wide dedup for free: two users pasting the same image only ever store it once.
Content is encrypted at rest under a server-held key, not a per-content key, so dedup on the plaintext hash still works.
Convergent per-content encryption was rejected: it leaks presence via confirmation attacks, and in a small trusted-operator deployment that trade buys nothing.
`canvas_objects` gets explicit `x, y, w, h` columns backed by a SQLite R-Tree virtual table, rather than coordinates buried in the `transform` JSON blob, because the bounded five-million-pixel world needs fast bounding-box viewport queries, and R-Tree is a built-in, purpose-fit answer to exactly that query shape.
Account deletion tombstones the `users` row: PII fields are scrubbed and `deleted_at` is set, all devices and refresh tokens are revoked, but authored messages are kept with the author shown as removed, since a message is also part of other participants' history, and erasing it unilaterally is worse than what the deletion actually asked for.
Multi-device is native to the schema: `devices` and `refresh_tokens` are per-device, while `read_states` is per-user, so read position syncs across a user's own devices as decided, without exposing it to anyone else.
Refresh tokens rotate on every use and carry a `family_id`.
A reused, already-rotated token revokes the whole family, cheap breach detection with no server-side session state beyond one row per device.

## 7. Migrations, retention, backup

Forward-only `.sql` files via sqlx's migrator, embedded in the binary, applied at startup.
Because both the official and self-hosted instance are single-process by decision, startup migration means a brief restart window rather than true zero-downtime, which is an honest trade-off given the lightweight goal, not an oversight.
Messages default to keep-forever with soft delete.
A per-group disappearing-message TTL is an explicit, off-by-default admin toggle swept by a background job.
Canvas replay ops and moderation-relevant audit facts are treated as two different retention classes: the fine-grained op log may be compacted for sync efficiency once no client needs full replay, while a lighter audit record of who created or removed which object is kept independently and longer.
Backup uses SQLite's `VACUUM INTO` for an atomic hot copy under WAL, far simpler than Postgres's WAL archiving for a self-hoster, scheduled by cron with grandfather retention.
Attachment blobs live on disk outside the database file and are backed up separately by tarball, keeping the database file itself small enough to snapshot quickly.

## Open questions

- Whether `roles.permissions` needs a second 64-bit column before v1 ships, once the exact permission list is finalized.
- Default disappearing-message and canvas-op compaction windows are product policy, left open here.
- Whether the official instance needs a lightweight per-tenant supervisor process to manage the fleet of single-community SQLite processes.
  That is a deployment-layer decision, not a schema one.
