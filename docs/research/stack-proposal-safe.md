# Server stack proposal: correctness and safety lens

Date: 2026-07-23.
Status: proposal for review, not yet accepted.

## Scope and lens

This proposal answers five foundational server questions for slim-m.
It is optimized for correctness and safety in a long-lived stateful realtime hub.
That means type safety, concurrency correctness, and compile-time or schema-verified database queries are weighted above raw development speed or minimal learning curve.
Every choice below is justified from the brief and the owner decisions directly, not from any prior project's toolchain.
The Voice Canvas is out of scope for this document except where the event-ordering scheme needs to generalize to it, since Voice Canvas implementation is handled separately.

Two owner decisions shape every answer here.
First, one backend deployment is one community, and the official instance runs single-process with state behind a swappable interface, with no multi-process on day one.
That removes distributed coordination from the problem entirely for v1: there is exactly one process minting IDs and writing to storage per deployment.
Second, the official instance and fully self-hosted servers run the same server image, and a self-hosted server for a handful of users must stay extremely lightweight.
That rules out any default that requires a second container or process just to run the server, while still needing a credible path to more scale on the official instance.

## 1. Server implementation language: Rust

### Choice

Rust, targeting the stable toolchain, using the async ecosystem built on Tokio.

### Rationale

A long-lived realtime hub holds many concurrent connections (text, voice signaling, screen-share signaling, and later Voice Canvas op streams) each mutating shared server-side state: channel membership, presence, per-channel event sequences, voice session rosters.
This is exactly the class of bug that shows up as intermittent data races, use-after-free, or torn state under load, and exactly the class of bug that is hardest to catch with tests alone because it depends on timing.
Rust's ownership and borrow-checker model turns most of these into compile errors instead of runtime incidents, and its `Send`/`Sync` traits make it a compile error to share non-thread-safe state across tasks by accident.
That is a direct match for the "concurrency correctness" half of this proposal's lens.
Rust also compiles to a small, dependency-free static binary with no garbage collector and no VM warm-up, which matches the brief's demand that a self-hosted server for a handful of users stay extremely lightweight: low idle CPU (no GC pauses to service), fast cold start, and a small resident memory footprint before any connections even arrive.
Its type system (sum types, exhaustive `match`, `Result`-based error handling with no silently-swallowed exceptions) also directly serves the "type safety" half of the lens: illegal states are unrepresentable more often than in most mainstream server languages, and error paths must be handled or explicitly ignored, not forgotten.

### Strongest alternative rejected: Elixir on the BEAM

Elixir and OTP are arguably the most purpose-built platform in existence for "long-lived stateful realtime hub": lightweight per-connection processes, a supervision tree that isolates and restarts failures without taking down the whole server, and a concurrency model built around message passing rather than shared mutable state, which sidesteps whole categories of races by construction.
It was seriously considered.
It is rejected as the primary pick for this proposal specifically because of the stated lens, not because it is a bad fit for the domain.
Elixir's safety comes from runtime supervision and crash-and-restart, not from static proof: the type system is dynamic, and while Dialyzer and typespecs give partial, best-effort static checking, they do not give the compile-time guarantee that an illegal state cannot be constructed or that two tasks cannot race on shared memory, which is what this lens is optimizing for.
Compile-time verified database queries are also weaker on this stack: Ecto changesets validate at runtime, not at compile time, and there is no direct equivalent to a macro that checks a literal SQL string against the real schema during `cargo build`.
The BEAM VM's baseline memory footprint is also higher than a static Rust binary, which cuts against the self-host lightweight requirement, though it is lighter than a JVM.

### Main risk

Rust has a real learning curve, especially in async code, where cancellation safety (what happens when a `.await` inside a `select!` branch is dropped mid-flight) is a genuine, easy-to-get-wrong subtlety that has bitten experienced teams.
Compile times are also slower than the alternatives, which can slow iteration during active development.
The brief wants the project to be "easy to contribute to," and Rust's ecosystem, while mature for this use case, has a smaller pool of contributors comfortable with it than Go, TypeScript, or Java.
This is mitigated by keeping the async surface area small and well-tested (thin connection-handling layer, most logic in plain synchronous, easily-testable functions), and by clippy plus mandatory code review as a standing practice, but it is a real ongoing cost, not a one-time one.

## 2. Web and WebSocket framework: axum

### Choice

axum, built on Tokio, Hyper, and Tower, for both the HTTP surface (auth, REST-ish resource endpoints, admin and diagnostics) and the WebSocket surface (the realtime event stream) in a single unified server process.

### Rationale

axum is maintained by the same working group that maintains Tokio itself, so it tracks the async runtime it depends on closely instead of drifting from it, which matters for a project meant to be sustainable over many years.
Its extractor model turns "does this request have a valid, authenticated, well-typed body" into a compile-time-checked function signature rather than a pile of manual runtime checks scattered through handlers, which is a direct, concrete instance of the type-safety lens applied to the request layer.
It sits on Tower, giving a composable, reusable middleware stack (timeouts, tracing, rate limiting, auth) that is shared, testable code rather than copy-pasted per-route logic.
Using one framework for both HTTP and WebSocket traffic keeps the server's surface area small, which matters both for the brief's "avoid a giant monolithic codebase" principle at the code level and for the "extremely lightweight" self-host requirement at the runtime level: one listener, one process, one dependency tree to reason about and patch.

### Strongest alternative rejected: Actix-web

Actix-web is the other mainstream production-grade Rust web framework and is a legitimate contender on performance benchmarks.
It is rejected here mainly on a correctness-lens basis.
Actix-web's history includes a well-known 2020 incident where an external audit found a large number of unnecessary `unsafe` blocks in its internals, several of which were genuine unsoundness bugs; the maintainer responded well and the ecosystem has since improved substantially, but for a proposal whose whole lens is compile-time and memory safety, a framework with that history warrants more scrutiny than one built from the start on the safe, boringly-typical Tokio and Tower stack that the rest of the Rust async ecosystem (including the database layer chosen below) already assumes.
Actix-web now also runs on Tokio underneath, so the practical runtime-compatibility gap between the two has narrowed, but the extra historical scrutiny still tips the choice toward axum.

### Main risk

axum's WebSocket support is intentionally low-level: it hands you a message stream and leaves backpressure, ping and pong keepalive, idle-connection reaping, and graceful shutdown to the application.
For a server meant to hold many long-lived connections, getting any of those wrong (for example, an unbounded per-connection outbound queue during a slow client) becomes a slow memory leak rather than a crash, which is a harder class of bug to catch in testing.
This is mitigated by treating connection lifecycle management as a first-class, well-tested module rather than inline handler code, but it is real work axum does not hand you for free.

## 3. Database engine and data-access approach: SQLite with sqlx, behind a swappable store trait

### Choice

SQLite in WAL (write-ahead log) mode as the default embedded database engine, accessed through sqlx with compile-time-checked queries, with all persistence routed through a repository trait so the storage backend is swappable without touching call sites.

### Rationale

The brief's database section explicitly asks to avoid premature complexity while still planning for long-term growth, and to optimize for efficient lookups, low storage overhead, and fast synchronization.
SQLite embedded directly in the same process the server already runs satisfies that directly: there is no second process to install, configure, back up, or tune, which is exactly what "a self-hosted server for a handful of users must stay extremely lightweight" requires, and it removes a network hop between the application and its data, which helps both latency and the "efficient network usage" principle.
Because the official instance and self-hosted servers run the same image, a default that works with zero extra infrastructure for the self-hoster and still scales adequately for the official instance at its current single-process, single-community scale (owner decisions 4 and 7) is the right fit for both deployment shapes at once.
sqlx's `query!`/`query_as!` macros validate the literal SQL text against the real database schema at compile time (either a live database during development or a checked-in offline query cache for CI), which is the concrete, literal match for "compile-time or schema-verified database queries" in this proposal's lens.
sqlx is also async-native on Tokio, so database calls integrate directly into the same async runtime as the WebSocket and HTTP layers without a blocking-thread bridge.
Wrapping all access behind a repository trait means the persistence backend is a swappable implementation detail, consistent with the swappable-interface philosophy the owner already applied to official-instance runtime state, and gives a documented, low-risk upgrade path to Postgres for the official instance specifically if it ever outgrows single-writer SQLite, without forking the codebase or rewriting call sites.

### Strongest alternative rejected: Diesel (typically paired with PostgreSQL)

Diesel is, if anything, an even stronger pure compile-time-safety story than sqlx: its query builder encodes the schema in the type system itself, so many invalid queries (wrong column type, wrong join, selecting a column that does not exist) are caught by the Rust type checker while the query is being built, not just when a fixed SQL string is checked against a schema.
It was seriously considered for exactly that reason.
It is rejected here because Diesel's core is synchronous by design; running it inside an async Tokio server means either accepting `spawn_blocking` bridging for every database call, which is itself a source of subtle correctness and resource-exhaustion risk in a connection-heavy hub (a saturated blocking thread pool under load degrades in ways that are hard to diagnose), or adopting `diesel-async`, a separately maintained, less battle-tested addition to the core project.
Pairing Diesel with Postgres as its natural default would also reintroduce the second-process problem for self-hosting that this proposal is specifically trying to avoid.
sqlx gives most of the same compile-time guarantee for the concrete, hand-written queries actually shipped, without the async-bridging tradeoff.

### Main risk

SQLite's single-writer model means only one write transaction commits at a time, even in WAL mode, which readers do not block.
Under bursty write load, such as fast fan-out across many active channels on a busier official instance, this can become a throughput ceiling; the mitigation is short, disciplined write transactions, a sane `busy_timeout`, and the already-planned escape hatch to Postgres behind the repository trait if the official instance's growth ever demands it.
Separately, sqlx's compile-time checking is only as good as the schema it checks against staying in sync with actual migrations; this needs to be enforced as a CI step (regenerating and diffing the offline query cache on every schema change) or the guarantee silently degrades to checking against a stale schema.

## 4. Event identity and total-ordering scheme: client-generated UUIDv7 identity, server-assigned per-stream monotonic sequence

### Choice

Every event (a chat message, a system event, and the same pattern for Voice Canvas operations when that work happens) gets two identifiers that serve two different purposes.
A UUIDv7 is generated client-side at creation time as a stable, globally unique identity: it lets the client optimistically render the event locally before the server has acknowledged it, and it doubles as an idempotency key if a send is retried.
A signed 64-bit integer sequence number is assigned by the server, monotonically increasing per stream (per channel, later per canvas session), and durably persisted in the same transaction as the event itself; this sequence, not the UUID, is the authoritative total order and the sync cursor clients use to ask "give me everything after sequence N" with no gaps and no duplicates.

### Rationale

Owner decisions 4 and 7 establish that a deployment is single-community and single-process, which means there is exactly one writer minting order for any given stream, with no distributed coordination problem to solve.
That makes a plain, durable, per-stream monotonic counter both sufficient and the simplest correct answer; anything more elaborate would be solving a problem this architecture does not have.
Splitting identity from order is what makes both jobs correct at once: identity needs to be constructible by the client before any round trip to the server, for good optimistic-UI local echo, while order needs to be assigned by the single authoritative writer to be trustworthy as a sync cursor.
A single field cannot do both well, since a client-constructed value cannot be a trustworthy total-order key without reintroducing exactly the distributed-uniqueness problem the single-process architecture was chosen to avoid, and a server-only sequence cannot be known to the client until after a round trip, which would delay local echo.
UUIDv7 specifically (over plain UUIDv4) is chosen for the identity half because it is time-sortable and therefore friendlier to database index locality and to log correlation during debugging, even though it is not relied upon for strict ordering.
Modeling identity and sequence as distinct types (not both left as bare integers or bare strings) is a small, concrete instance of the type-safety lens: it becomes a compile error, not a runtime bug, to accidentally compare or sort by the wrong field.
This same two-part pattern is intended to generalize directly to the Voice Canvas's operation log (strokes, moves, resizes) once that work begins, since it is the same "many concurrent authors, one authoritative per-stream order" shape.

### Strongest alternative rejected: Snowflake-style IDs (Twitter or Discord style)

A single 64-bit ID that packs a timestamp, a worker or shard identifier, and a per-millisecond counter into one field, used as both identity and order, is the well-precedented choice for exactly this domain, and Discord's own production system uses this pattern.
It is rejected as the default here specifically because it is solving a distributed problem: the worker-id component exists to let multiple independent ID-minting nodes generate non-colliding, roughly-ordered IDs without talking to each other.
This architecture, by owner decision, has exactly one writer per deployment, so that machinery buys nothing today and adds real cost: worker-id allocation and persistence, backwards-clock handling if the host's clock steps, and bit-packing and unpacking logic, all to solve a coordination problem that does not exist yet.
It also conflates identity and order in one field, which makes clean client-side optimistic-UI local echo harder, since constructing a valid-looking snowflake client-side reintroduces the very distributed-uniqueness problem the single-process design sidesteps.
If the product ever adopts multi-process sharding for the official instance, a snowflake-style scheme (or handing out worker-id ranges to processes) is the documented, sensible next step, but adopting it now would be premature for the architecture as decided.

### Main risk

The per-stream sequence counter must be persisted durably in the same transaction as the event it orders, not merely held in memory and incremented, or a crash and restart can reuse or skip sequence numbers in a way clients cannot reconcile against their local cache.
More fundamentally, this whole scheme leans on the single-process assumption in owner decision 7; if the official instance ever needs true multi-process horizontal scaling, the "one authoritative writer per stream" property that makes a plain monotonic counter sufficient no longer holds, and the ID scheme would need deliberate revisiting at that point.
That is an accepted, documented future cost, not a v1 blocker, since decision 7 already treats a shared backplane as something to add only when scale actually demands it.

## 5. Client-server wire format: Protocol Buffers over WebSocket, JSON for humans-only surfaces

### Choice

Protocol Buffers as the primary typed wire format for both the realtime WebSocket event stream and the HTTP request and response bodies, generated from a single `.proto` schema shared by the Rust server (via `prost`) and the Flutter and Dart client (via `protoc-gen-dart`).
Plain JSON is kept only for surfaces where human readability matters more than efficiency or cross-language type-sharing, such as health checks, metrics, and ad hoc admin diagnostics.

### Rationale

A single schema of record, compiled into typed code on both the Rust and Dart sides, is the direct way to extend the compile-time type-safety lens across the network boundary itself, not just within each side individually: a field renamed or retyped on one side becomes a build failure on that side rather than a runtime parsing surprise discovered by a user.
Protobuf's binary encoding is materially smaller and cheaper to parse than JSON, which matters for the brief's "efficient network usage" principle directly, and matters especially for the Voice Canvas's likely high-frequency operation stream (in-progress strokes, live cursor and window-move updates) and for battery-constrained mobile clients, where parsing cost is not free.
Protobuf's field-number-based schema evolution model is built for exactly the situation this project will actually be in for years: self-hosted servers and official mobile clients that are not always upgraded in lockstep, where the wire format must tolerate a client and server a few versions apart from each other gracefully.
Using the same format for HTTP bodies as for the WebSocket stream, rather than JSON for one and protobuf for the other, keeps the wire layer to one thing to reason about and test instead of two.

### Strongest alternative rejected: JSON with hand-written or generated DTOs

JSON is simpler to debug with plain browser devtools or `curl`, has zero codegen step, and is the default most contributors will already be comfortable with.
It is rejected as the primary format specifically because it does not, on its own, give a single shared schema of record between Rust and Dart: without additional tooling (a hand-maintained JSON Schema plus codegen for both languages, which starts to reinvent what protobuf already gives natively) the two sides' types can drift silently out of sync, discovered only at runtime, which directly cuts against this proposal's lens.
It is also measurably heavier on the wire and more expensive to parse than a binary format, which matters for both network efficiency and mobile battery impact, both explicit brief principles.
JSON is not discarded entirely: it is kept for the low-frequency, human-facing surfaces (health, metrics, admin diagnostics) where its readability is worth more than its overhead, since those are not on the realtime hot path.

### Main risk

A single shared schema across two independently-versioned, independently-deployed codebases (official mobile client, official server, and any number of self-hosted servers running older releases) makes schema-evolution discipline a permanent, load-bearing process requirement, not a one-time setup cost.
A mishandled breaking change, such as reusing a field number or silently changing a field's meaning, could corrupt or misinterpret data for a self-hoster who has not upgraded promptly, and would be hard to notice quickly since the payloads are not human-readable on the wire.
This is mitigated by CI-enforced schema-compatibility checks (breaking-change detection against the previous schema on every change) and a strict "additive only, never renumber or repurpose a field" convention, plus a dev-only text-format or JSON-transcoding path for local debugging, but it is an ongoing discipline the team must maintain for as long as the project lives.

## How the five choices fit together

Rust and axum give a small, memory-safe, single static binary that starts fast and idles cheap, which is what the self-host requirement demands and what a realtime connection hub needs to be correct under concurrency.
SQLite embedded in that same binary keeps a self-hosted deployment to one process and one file, while the repository-trait abstraction keeps the door open to Postgres for the official instance without forking the codebase, consistent with the swappable-interface philosophy the owner already chose for runtime state.
sqlx ties the database layer's compile-time guarantees directly to the language choice's own compile-time guarantees, so "does this query match the schema" and "is this state safely shared across tasks" are both checked at the same `cargo build` step.
The identity-plus-sequence event scheme is the direct, minimal consequence of the single-process, single-community architecture the owner already decided on: it needs no distributed coordination because there is no distributed writer to coordinate, today.
Protocol Buffers carries all of that type safety across the wire to the Flutter client, so the correctness story does not stop at the server's process boundary.
Every piece here is deliberately boring and well-precedented on its own; the correctness comes from how consistently the same two properties (compile-time-checked types, and a single authoritative writer per stream) are applied across all five layers at once.
