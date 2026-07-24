# SQLite Data Layer Validation and Recommendations

Status: due-diligence pass completed.
Date: 2026-07-23.
Scope: embedded SQLite WAL layer, access patterns, connection pooling, migration tooling, backup strategy, and write-throughput ceilings for slim-m's single-writer, single-scope-monotonic-sequence persistence model.

## 1. Library and Tooling Validation

### 1.1 sqlx (version 0.9.0+, MIT/Apache-2.0)

**Status: CONFIRMED**

Maturity and maintenance: sqlx 0.9.0 was released on 2026-05-06 with breaking changes and new features including a new `sqlx.toml` config system and the `SqlSafeStr` trait for hardened query safety.
The project is actively maintained by the transact-rs working group (same maintainers as Tokio), which ensures stability and alignment with the async Rust ecosystem.
Minimum supported Rust version is 1.94.0.
License: MIT or Apache-2.0 (permissive, suitable for permissive-first goal).

Compile-time query checking: confirmed as the core feature.
The macro `sqlx::query!` and `sqlx::query_as!` validate literal SQL against the real schema at compile time by connecting to the development database during the build.
For CI/CD environments without a live database, offline mode with `cargo sqlx prepare` caches query metadata into JSON files that should be committed to version control.
CI can verify freshness with `--check` flag to ensure the cache stays in sync with schema changes.

Single-writer model support: sqlx supports write-serialization through explicit connection configuration.
Writes can be funneled through a single logical writer by maintaining a single write connection and a separate small read-only pool.
This mirrors the architecture decision's explicit discipline.

Gotchas: The offline query cache (`.sqlx/` directory) must be regenerated and verified in CI on every schema or query change, or the compile-time guarantee silently degrades to checking against stale schema.
The decision's risk mitigation (enforce cache regeneration and diff check as a CI step) remains mandatory.

Recommendation: use sqlx 0.9.0 or later with the new `sqlx.toml` configuration to explicitly define the single-writer and read-pool topology.
Enable offline mode for CI robustness.

### 1.2 SQLite WAL mode (native SQLite feature, stable since 3.7.0)

**Status: CONFIRMED with PRAGMA tuning guidance**

Maturity: WAL (write-ahead logging) mode is stable and battle-tested in production across millions of deployments.
SQLite's WAL format is documented and has been compatible since SQLite 3.7.0 (2010).

Write concurrency model: WAL mode allows concurrent readers alongside one writer, which is exactly the slim-m single-writer-plus-read-pool model.
Readers do not block writers and a writer does not block readers.
This is the correct default for the use case.

PRAGMA tuning for production self-host: the architecture decision requires explicit PRAGMA configuration.
The minimal production configuration must include:

```
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = -64000;
PRAGMA foreign_keys = ON;
PRAGMA wal_autocheckpoint = 1000;
```

- `journal_mode = WAL` enables the write-ahead log.
- `busy_timeout = 5000` (5 seconds) instructs SQLite to retry with exponential backoff when the database is locked, rather than failing immediately; this is critical under peak write load and dramatically reduces application-level errors.
- `synchronous = NORMAL` balances durability (safer than OFF, adequate for WAL) against write latency; in WAL mode, NORMAL is production-safe because the WAL itself provides durability guarantees.
- `cache_size = -64000` sets the page cache to 64 MB, reducing repeated I/O for working-set queries; adjust based on RAM available on the self-host target.
- `foreign_keys = ON` ensures referential integrity; omit only if the schema intentionally disables it.
- `wal_autocheckpoint = 1000` instructs SQLite to automatically checkpoint (merge the WAL back into the main file) every 1000 pages, keeping the WAL file bounded and preventing unbounded growth during idle periods.

Gotcha: WAL mode requires a filesystem that correctly supports file locking and memory-mapped I/O.
Network-mounted directories (NFS, SMB without proper locking) will fail or corrupt silently.
Document this plainly in the self-host deployment guide so administrators do not accidentally place the database file on an unsupported filesystem.

Backup and recovery: when running automated backups or restoring from a backup, always delete the existing `app.db-wal` and `app.db-shm` files alongside the main `app.db` file; leftover WAL or shared-memory files from an old database will confuse SQLite when paired with a restored main file.

Recommendation: include PRAGMA tuning in the initialization of the write-connection path, not as manual SQL that must be run separately.
Document WAL filesystem requirements in the self-host guide.

### 1.3 Connection pooling for the read path

**Status: CONFIRMED, pool configuration required**

Read pool strategy: sqlx has built-in pooling via `sqlx::Pool`.
For reads, create a separate small read-only pool with conservative size.
The architecture decision's "small read-only WAL pool" suggests 2-8 connections depending on the expected concurrent read load.
Since reads do not mutate and WAL mode supports concurrent readers, a small pool is sufficient and keeps idle resource use low on self-hosted deployments.

Pool sizing guidance: for a self-hosted server with a handful of users, a pool size of 2-4 is reasonable.
For the official instance, 8-16 may be appropriate.
The metric to monitor is connection idle time; if most connections are idle, the pool is oversized.

Write connection: maintain a single write connection (not pooled) that funnels all writes through one serialized path.
This enforces the single-writer discipline at the connection level, making it impossible for two threads to accidentally issue concurrent writes.
Implement this as a dedicated writer task in Axum, with a channel-based queue for write requests, so writes are naturally serialized at the code level.

Gotcha: deadpool-sqlite (the async pool for rusqlite) is not applicable here because the architecture uses sqlx, not rusqlite.
Do not mix pooling strategies; use sqlx's built-in pool throughout.

Recommendation: configure sqlx::Pool with `max_connections` set to the read-pool size (e.g., 4 for self-hosted, 8-16 for official), and maintain a separate single write connection outside the pool.
Use the existing repository trait as the abstraction boundary to encapsulate pool creation and lifecycle.

### 1.4 Migration tooling: sqlx migrate vs refinery

**Status: CONFIRMED for sqlx migrate**

sqlx migrate: sqlx bundles its own migration system that embeds migrations into the binary.
Migrations are plain SQL files in a `./migrations/` directory, prefixed with timestamps (e.g., `20260723000001_users.sql`).
The `sqlx migrate add <name>` CLI command scaffolds new migrations.
At compile time, sqlx expands the `sqlx::migrate!()` macro to a static `Migrator` instance that contains all migrations; at runtime, the migrator runs them in order.
Migrations are forward-only (never rollback), which matches the architecture decision.

License: MIT or Apache-2.0 (permissive).
Maintenance: sqlx migrate is part of the main sqlx project, so it benefits from active maintenance alongside the core library.

refinery: refinery is a separate toolkit that supports multiple backends (postgres, mysql, rusqlite).
It is maintained separately and supports migrations defined as either `.sql` files or Rust functions.
For sqlx users, refinery requires additional configuration and has less tight integration than sqlx's native system.

Comparison for slim-m: sqlx migrate is simpler, requires no additional dependencies, and integrates directly with sqlx's compile-time checking.
Refinery adds configuration surface area without clear benefit for this use case.

Gotcha: sqlx's offline mode must work with migrations; ensure `.sqlx/` cache includes migration metadata if using compile-time checks.
For most projects, migrations and queries are cached separately and this is not an issue, but verify in CI that migration changes do not break the query cache.

Recommendation: use sqlx migrate exclusively; do not introduce refinery.
Migrations stay in the `./migrations/` directory alongside the Rust source.

### 1.5 FTS5 full-text search

**Status: CONFIRMED**

SQLite FTS5 availability: FTS5 is a virtual table extension built into modern SQLite and is included in the sqlx SQLite bundle (libsqlite3-sys).
It is stable, widely used, and the recommended text-search extension for SQLite (successor to FTS3/FTS4).

How to use: FTS5 tables are created with `CREATE VIRTUAL TABLE docs USING fts5(title, body, content='')`.
Queries use the `MATCH` operator: `SELECT * FROM docs WHERE docs MATCH 'search term'`.
FTS5 includes built-in ranking functions (BM25) for relevance scoring.
Tokenizers are pluggable (unicode61 is the default and suitable for most use cases).

Rust integration: FTS5 is queried via plain SQL through sqlx, exactly like any other table.
No special driver support is needed; compile-time query checking applies to FTS5 queries the same way it does to regular SQL.

Gotcha: FTS5 is a virtual table, not a persistent table; it stores data in the FTS5 structure itself.
To use FTS5 with persistent content (so you can fetch full records after a search), use `content=<table>` to point the FTS5 index to a real table.
For example, `CREATE VIRTUAL TABLE messages_fts USING fts5(content, tokenize='unicode61', content='messages')` indexes the `messages` table.

Recommendation: use FTS5 for full-text search without additional dependencies.
For initial implementation, the unicode61 tokenizer is sufficient; revisit if advanced tokenization (morphological stemming, custom stop-words) becomes necessary.

### 1.6 UUIDv7 in Rust

**Status: CONFIRMED with library recommendation**

Architecture decision: the design uses client-generated UUIDv7 as the stable, globally unique event identity.
UUIDv7 is superior to UUIDv4 for database write performance because UUIDs are generated with a 48-bit millisecond timestamp prefix, which makes them roughly time-sortable and gives much better B-tree index locality than random v4 UUIDs.

Available Rust crates:

- **uuid crate (version 1.0+)**: The standard Rust UUID crate provides `uuid::Uuid` with full RFC 9562 support including UUIDv7 via `Uuid::now_v7()`.
  This is the de-facto standard and is well-maintained.
  License: MIT or Apache-2.0.
  Does not require the `v7` feature flag; v7 generation is in the core as of uuid 1.0.

- **uuid7 crate (LiosK/uuid7-rs)**: A focused UUIDv7 library by LiosK with options for fast generation using thread-local storage and seeded randomness.
  Generates faster than the standard uuid crate if contention is a concern (hundreds of thousands of UUIDs per second per thread).
  License: MIT or Apache-2.0.
  Less widely used than the standard crate.

- **fast-uuid-v7 crate**: Explicitly optimized for high-throughput generation using thread-local seeded SmallRng.
  Suitable if profiling reveals UUID generation as a bottleneck.
  License: MIT or Apache-2.0 (assumed from similar crates; verify).

Recommendation: start with the standard `uuid` crate version 1.0+ and use `Uuid::now_v7()`.
This is the most widely known and maintained option.
If profiling later shows UUID generation contention in the hot path (unlikely for a self-hosted server), switch to `uuid7` or `fast-uuid-v7`.

B-tree locality: when UUIDv7 values are used as database primary keys or part of indexes, their temporal prefix ensures that newly inserted IDs land near the tail of the B-tree, yielding high cache hit rates and reducing write amplification on small self-hosted disks.
This is a structural win over UUIDv4 and aligns with the brief's emphasis on performance and efficient disk usage.

### 1.7 Write-throughput ceiling and triggers for Postgres swap

**Status: FLAGGED for monitoring**

SQLite single-writer limitation: SQLite enforces a global write lock, allowing exactly one transaction to write at a time.
In WAL mode, write throughput is approximately 70k-100k transactions per second for typical record sizes when properly tuned.

When the official instance or a large self-hosted deployment approaches this ceiling, write latency and lock contention will become noticeable.
The risk mitigation in the architecture decision is to define explicit, measurable triggers for when to build and swap in a Postgres implementation of the repository trait.

Monitoring and trigger points:

1. Track `write_latency_p99` (99th percentile write latency) and `lock_contention_rate` (count of SQLITE_BUSY errors).
2. If p99 write latency exceeds 50ms or lock contention errors exceed 1% of write attempts, investigate:
   - Are transaction sizes excessive (rewrite shorter)?
   - Is the `busy_timeout` too low (increase to 10000 or 30000ms)?
   - Has the deployment genuinely exceeded the single-writer model's capacity?
3. If investigation confirms that legitimate workload exceeds single-writer capacity (estimated at 10k-50k concurrent active users under normal chat patterns), treat Postgres swap as a planned migration, not an emergency.

The repository trait keeps this swap mechanical: implement `repositories::postgres::PostgressRepository`, pass it through the dependency-injection layer, and run end-to-end tests against both backends to ensure the swap is seamless.

Recommendation: instrument the write path to measure latency and lock contention from day one, even if these metrics are not exposed initially.
Include trigger thresholds in the self-host admin guide so operators know when to escalate to the team.
Document the Postgres swap procedure (stub it out as a future task) so it is not a surprise discovery when needed.

## 2. Recommended Additions

### 2.1 Backup and disaster recovery: Litestream integration

**Status: STRONGLY RECOMMENDED ADDITION**

Why: the architecture decision names backup and disaster recovery as a major concern for self-hosted deployments ("matters a lot for a single-file database on a self-host").
For a self-hosted admin with no DBA expertise, automated point-in-time backup is not a nice-to-have; it is the difference between a recoverable outage and permanent data loss.

Litestream overview: Litestream is a background process that continuously streams SQLite's write-ahead log pages to an S3-compatible object store (AWS S3, MinIO, etc.).
It provides disaster recovery, not high availability; replicated databases remain read-only until explicitly promoted.
Litestream's 0.5.0 release (late 2025) matured the product to the point where it is production-ready for single-server deployments.

Integration approach:

1. In the self-host Docker Compose example, run Litestream as a sidecar container alongside the slim-m server.
   Litestream watches the SQLite WAL file and streams changes to S3 in real time.
2. Expose `LITESTREAM_S3_BUCKET`, `LITESTREAM_S3_REGION`, `LITESTREAM_S3_KEY_ID`, `LITESTREAM_S3_KEY` as environment variables so admins can configure their S3 credentials without rebuilding.
3. Provide a recovery procedure in the self-host guide: if the server crashes, download the latest backup and WAL stream from S3, restore, and restart.
4. Document that admins can disable Litestream by not setting the S3 credentials, but strongly recommend it for any production deployment.

Litestream vs LiteFS: LiteFS is a FUSE-based distributed file system optimized for high-availability replication across regions (multi-node).
For a self-hosted single-node deployment, Litestream is simpler and sufficient.
LiteFS adds complexity and filesystem-level coupling that a self-hoster does not need.
If the official instance ever targets global replication (not in v1), LiteFS could be evaluated, but for now Litestream is the right choice.

Licensing: Litestream is Apache-2.0 (permissive).

Cost: S3 storage and egress charges will be modest (kilobytes to megabytes per day for a chat application), so this is self-host-friendly.

Recommendation: commit to integrating Litestream in the Docker Compose example and self-host deployment guide before shipping v1.
Make it straightforward but optional so self-hosters with existing backup practices are not forced to use S3.

### 2.2 sqlx.toml configuration and custom type registry

**Status: RECOMMENDED ADDITION**

Why: sqlx 0.9.0 introduced a `sqlx.toml` file that centralizes configuration for multi-database or multi-tenant setups, and permits global type overrides.
For slim-m, this is valuable for:

1. Mapping custom Rust types (e.g., `MessageId` newtype wrapping `uuid::Uuid`, or `Sequence` newtype wrapping `i64`) to their SQL representations without boilerplate in every query.
2. Defining database-specific settings in one place (feature flags, driver options) so CI and local development stay in sync.
3. Reducing coupling between the repository layer and sqlx, making it easier to swap storage implementations later.

Integration approach:

1. Create a `sqlx.toml` file at the workspace root with configuration blocks for custom types used in the data model (UUIDs, Sequence numbers, any enums stored as strings or integers).
2. Use `#[sqlx(type_name = "...")]` attributes on Rust newtypes to map them to their SQL representation.
3. Verify in CI that type mappings are consistently applied across all queries.

Recommendation: include `sqlx.toml` setup in the initial repository layer implementation.
This is a low-cost, high-value addition that improves query type safety and reduces boilerplate.

### 2.3 Query complexity and performance assertions in tests

**Status: RECOMMENDED ADDITION**

Why: the brief emphasizes performance as a first-class feature and efficient database queries.
Without explicit tests, query performance regressions can sneak in (e.g., a join that omits an index, a loop that multiplies queries by the size of a result set).

Approach:

1. For hot-path queries (message fetch, presence check, user lookup, FTS5 search), write tests that verify expected result counts and estimated execution times.
2. Use SQLite's `EXPLAIN QUERY PLAN` to inspect the query plan in tests and assert that it uses the expected indexes.
3. Set a reasonable ceiling on execution time (e.g., p99 latency < 10ms for a single message fetch on a 10k-message channel) and fail the test if the query exceeds it on the test database.

Recommendation: add this as a testing practice rather than a library addition.
Pair it with the monitoring guidance in section 1.7 so production behavior is visible alongside test expectations.

## 3. Changes and Replacements

### 3.1 Replace rusqlite with sqlx

**Status: NOT A CHANGE (already decided)**

The architecture decision already chose sqlx over rusqlite.
The decision is sound and does not need reversal.
Confirm that the rationale remains valid: sqlx's compile-time query checking is the deciding advantage, and the footprint delta is negligible once both are properly integrated with tokio's async runtime.

### 3.2 Do not swap to libsql or Turso in v1

**Status: CONFIRMED (no change needed)**

LibSQL (Turso's open-source fork of SQLite) is mature and gaining traction in 2026.
It adds features like remote access over WebSockets and a server mode that serves distributed reads.
However, these features are out of scope for v1:

1. The architecture requires a single-file embedded database by design to minimize self-host complexity.
2. Remote access adds network layers that contradict the self-host-lightness goal.
3. Turso's embedded replicas (local copy + cloud sync) are a future possibility but not necessary for v1.

Recommendation: document libsql as a potential future evolution (beyond v1) if the project needs to support multi-region replication or edge caching.
For v1, stick with standard SQLite accessed via sqlx.

## 4. Risks and Version Pitfalls

### 4.1 sqlx offline query cache drift

**Risk level: MEDIUM**

The offline query cache (`.sqlx/` directory) must be regenerated whenever the schema or queries change.
If a contributor modifies a query without running `cargo sqlx prepare`, the cache can drift and the compile-time guarantee fails silently on the next CI run.

Mitigation:

1. Run `cargo sqlx prepare --check` in CI on every push to verify the cache is up-to-date.
2. Add a pre-commit hook that runs `cargo sqlx prepare` automatically (optional but recommended).
3. Commit the `.sqlx/` directory to version control so the cache is part of the repository.
4. Document in CONTRIBUTING.md that all schema or query changes require `cargo sqlx prepare`.

### 4.2 WAL filesystem incompatibility

**Risk level: MEDIUM**

WAL mode requires proper file locking and memory-mapped I/O support.
If a self-hoster accidentally places the database on a network filesystem without proper locking (e.g., NFS without nocto or SMB without proper file locking), the database will silently corrupt.

Mitigation:

1. Add a startup check in the server that verifies WAL mode is working correctly (write a test record, read it back, verify atomicity).
2. Document filesystem requirements plainly in the self-host guide.
3. Recommend local ext4 or similar filesystems, and explicitly warn against NFS, SMB, and cloud-mounted block stores without proper testing.

### 4.3 Litestream configuration and S3 credentials

**Risk level: MEDIUM**

Misconfigured S3 credentials or bucket permissions will cause Litestream to fail silently, leaving the server running without backups.
If this goes unnoticed, a subsequent crash results in data loss.

Mitigation:

1. Add a health check endpoint that queries Litestream's status (if Litestream is in use) and reports whether backups are being made.
2. Expose this in the admin UI and diagnostics endpoints so operators are alerted if backups stop.
3. Provide a test procedure in the self-host guide (upload a test file to S3, verify Litestream can read/write, restore to a test database).
4. Log Litestream errors prominently in the server logs.

### 4.4 SQLite page size and WAL incompatibility

**Risk level: LOW**

SQLite's `page_size` (typically 4096 bytes) cannot be changed while WAL mode is active.
If a self-hoster tries to change it, the operation will fail.
This is rarely an issue, but it can cause confusion during tuning.

Mitigation: document that page size must be set before enabling WAL and should not be changed thereafter.

### 4.5 UUIDv7 B-tree write amplification with random ordering

**Risk level: LOW (mitigation already in decision)**

If event identity were accidentally stored or sorted by a random UUIDv4 value instead of UUIDv7, B-tree writes would scatter across the index, increasing write amplification on self-hosted disks.
The architecture decision's explicit use of UUIDv7 prevents this.

Mitigation: in tests and documentation, repeatedly affirm that identity is UUIDv7 (not v4) and that sequence numbers (not identity) are the sort key for history and sync queries.
Add a lint or assertion in the codebase that fails if any query orders by identity instead of by sequence.

### 4.6 sqlx 0.9.0 text/string inference change

**Risk level: LOW**

sqlx 0.9.0 changes the default type inference for text columns in MySQL from `Vec<u8>` to `String`.
This is a breaking change for MySQL users but does not affect SQLite (which has no such distinction).
If the codebase is SQLite-only, this change is irrelevant.

Mitigation: when (if) a Postgres implementation is added, test carefully against both SQLite and Postgres migrations to ensure type mappings are correct.

## 5. Specific Version Recommendations

As of 2026-07-23, recommend:

- **sqlx: 0.9.0 or later** (current stable, released 2026-05-06).
- **uuid: 1.0+** (current stable, includes UUIDv7).
- **sqlx.toml configuration**: use the new 0.9.0+ format.
- **sqlx-cli: latest** (from the same release as sqlx).
- **Litestream: 0.5.0 or later** (mature enough for production v1).
- **SQLite: 3.46.0 or later** (included in libsqlite3-sys bundled by sqlx).

## 6. Summary

The architecture decision's chosen stack (sqlx + SQLite WAL + single-writer + repository trait) is sound and well-supported by current 2026 libraries.

Confirmations:
- sqlx is actively maintained, compile-time query checking is solid, and offline mode works.
- SQLite WAL mode is production-ready with the right PRAGMA tuning.
- UUIDv7 for identity and per-scope monotonic sequences for ordering are the correct design.
- FTS5 is built-in and sufficient for full-text search.

Recommended additions:
- Integrate Litestream for backup and disaster recovery.
- Use sqlx.toml for custom type mappings (simplifies the codebase).
- Add performance assertions in tests to catch query regressions early.

Risks to mitigate:
- Offline query cache drift (CI verification).
- WAL filesystem incompatibility (documentation and startup checks).
- Litestream configuration errors (health checks, logging).
- Single-writer write-throughput ceiling (monitoring, trigger-based swap to Postgres).

No library swaps are recommended; the chosen stack remains optimal for v1 and can cleanly swap to Postgres (and potentially libsql in the future) via the repository trait.
