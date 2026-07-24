# Foundational server stack decision

Status: accepted for implementation.
Date: 2026-07-23.
Decider: chief architect.
Scope: the core slim-m chat and control-plane server that the Flutter client talks to for text messaging, voice and screen-share signaling, accounts, invites, and administration.

This document decides the single foundational server stack by weighing three independent proposals, each written to a different lens: [lean](stack-proposal-lean.md) (self-host footprint), [maintainable](stack-proposal-maintainable.md) (contributor pool and long-term maintainability), and [safe](stack-proposal-safe.md) (correctness and type safety).
Where the proposals agree, I say so and adopt the consensus with the strongest combined mitigations.
Where they disagree, I resolve it explicitly and say which lens won and why.

## Ground rules honored in this pass

Every choice below is decided on first principles plus the [brief](../BRIEF.md) and the [owner decisions](../decisions/0001-owner-decisions.md).
No choice is justified by "a prior project already used this" or "reuse the existing pattern," and none of them consulted or replicated the off-limits echo-messenger reference in any way.
The Voice Canvas wire format and coordinate handling are out of scope here and are decided separately.
The push relay is a separate service adapted from check-in-relay and is not decided here.

Fixed inputs treated as constraints, not re-litigated:

- The client is Flutter, targeting iOS and Linux (Fedora) first, Android next.
- The official instance is single-process with state behind a swappable interface, and a shared backplane is added only when scale actually demands it.
- One backend deployment is one community, so the server needs no multi-tenant isolation in v1.
- Transport-only encryption for v1 (TLS 1.3, server holds plaintext), with per-device identity keys pre-wired for later opt-in end-to-end encrypted DMs, so the wire format must remain compatible with that later addition.
- The official instance and every self-hosted server run the same server image.
- A self-hosted server for a handful of users must stay extremely lightweight, and performance is a first-class feature.

## Summary of decisions

| Question | Decision |
|---|---|
| Server language | Rust (stable toolchain, async on Tokio) |
| Web and WebSocket framework | Axum, on Tokio, Hyper, and Tower |
| Database engine | SQLite in WAL mode, embedded in the server process |
| Data access | sqlx with compile-time-checked queries, a single serialized writer path plus a read-only connection pool, plain-SQL migrations, all behind a repository trait swappable for Postgres later |
| Event identity | Client-generatable UUIDv7 |
| Total ordering | Server-assigned, per-scope, strictly monotonic signed 64-bit sequence number, persisted in the same transaction as the event |
| Wire format | JSON over HTTP and WebSocket, schema-first from a single OpenAPI and JSON Schema source of record with CI-enforced codegen for Dart and Rust, permessage-deflate on the socket, a compact binary encoding reserved as a documented additive escape hatch for measured hot paths |

## 1. Server language: Rust

### Decision

Rust on the stable toolchain, with async handled by Tokio.

### The disagreement and how I resolved it

Two proposals (lean and safe) chose Rust; the maintainable proposal chose Go.
This is the single most consequential fork in the whole stack, so I weighed it directly rather than counting votes.

The maintainable proposal's case for Go is genuine and I do not dismiss it: a single static binary, a deliberately small language with one enforced formatter, and the largest backend-focused contributor pool of the realistic options, which serves the brief's "easy to contribute to" goal.
The case against Go, for this specific product, comes down to two structural properties that the brief weights heavily and that Go cannot match by tuning.

First, idle footprint.
The brief hammers idle RAM, idle CPU, fast startup, and "extremely lightweight" self-hosting repeatedly, and it names performance a first-class feature.
A self-hosted server for a handful of users spends nearly all of its life idle, holding a few long-lived WebSocket connections open and doing almost nothing.
In that state the dominant cost is the runtime itself, and Go's garbage collector is a real, if modest, tax on exactly the two hardest axes here: it keeps heap headroom above live data, and its runtime wakes periodically even under zero load, which works against a target of effectively zero idle CPU.
Rust has no garbage collector, so there is no reserved GC heap and no scavenger thread waking the process on a timer while nothing happens.
That is a structural win, not a tuned one.

Second, correctness under concurrency.
The server is a long-lived stateful realtime hub: many concurrent connections each mutating shared state (channel membership, presence, per-scope sequences, voice rosters).
This is precisely the class of bug that surfaces as an intermittent data race or torn state under timing-dependent load, and precisely the class that tests catch poorly.
Rust's ownership model and its Send and Sync traits turn most of these into compile errors, so a whole category of race becomes unrepresentable rather than a silent incident on a self-hosted box that nobody is actively watching.
For a project meant to be beautifully engineered and sustainable over many years of unattended operation, that guarantee is worth more than the iteration-speed and onboarding advantages Go offers.

The tie-breaker is the weighting the brief and the project's own engineering standard impose: do not optimize for the fastest MVP, prefer quality, robustness, scalability, and long-term maintainability, and do not give much weight to development cost.
Go's advantage lives mostly on the development-cost and onboarding axis; Rust's advantages live on the performance, correctness, and long-lived-robustness axes the brief prizes.
Under that weighting, Rust wins, and Go becomes the named fallback if contributor onboarding ever proves to be the actual binding constraint in practice rather than a theoretical one.

Elixir on the BEAM (the safe proposal's rejected alternative) is the most purpose-built platform for a realtime hub, but its safety is runtime-supervision-based rather than compile-time-proven, its baseline memory footprint is higher than a static Rust binary, and it has no compile-time query verification, so it loses on both the footprint and the compile-time-correctness axes that decided this.
JIT and VM runtimes (Node, JVM, CPython) lose on all of cold start, steady-state CPU predictability, and baseline heap size before a single connection is served.
Zig or C would produce the smallest binaries but lack a mature, battle-tested async HTTP, WebSocket, TLS, and SQLite stack, which is a correctness and security risk not worth taking for a marginal size win in a server that handles authentication and user data.

### Main risk and mitigation

Rust's learning curve and compile times are a real, ongoing cost against "easy to contribute to," and async Rust in particular has sharp edges around trait bounds, pinning, and cancellation safety inside select branches.
Mitigate by keeping the async surface area small and conventional, pushing most logic into plain synchronous, easily-testable functions with only a thin async connection-handling layer, documenting the concurrency patterns the codebase actually uses, and standing up clippy plus mandatory review as a permanent practice.

## 2. Web and WebSocket framework: Axum

### Decision

Axum, built on Tokio, Hyper, and Tower, serving both the HTTP surface (accounts, channels, invites, admin, diagnostics) and the WebSocket surface (the realtime event stream) in one process.

### The disagreement and how I resolved it

Both Rust proposals chose Axum, and the maintainable proposal's framework pick (net/http plus chi plus coder/websocket) falls away with the language choice.
So the live question is Axum versus Actix-web, and both proposals reject Actix-web, from different angles that reinforce each other.

Axum is maintained by the same working group as Tokio, so the framework tracks the runtime it depends on instead of drifting from it, which matters for a project meant to last years.
Its extractor model turns "is this request authenticated and well-typed" into a compile-time-checked function signature rather than manual runtime checks scattered through handlers, which extends the language's type-safety property into the request layer.
WebSocket upgrade is a first-class extractor, so the connection-hub code sits next to the routing layer rather than in a second library with its own conventions.
Its Tower middleware is opt-in, so a lean self-host build only compiles in the tracing, compression, or rate-limiting layers it actually uses, which keeps both binary size and idle background work down.

Actix-web is competitive on raw throughput, but throughput at a handful-of-users scale is nowhere near the bottleneck, and its actor-model heritage adds conceptual and binary surface area this project does not need now that both frameworks sit on Tokio.
Its history of internal unsafe-code unsoundness, since remediated, still warrants more scrutiny than the boringly-typical Tokio and Tower stack the rest of the chosen ecosystem already assumes.
Hand-rolling routing and upgrades directly on Hyper was also rejected: it trades a small size saving for a permanent maintenance burden reimplementing routing, extraction, and connection upgrade by hand.

### Main risk and mitigation

Axum's WebSocket support is intentionally low-level: it hands you a message stream and leaves backpressure, ping and pong keepalive, idle-connection reaping, and graceful shutdown to the application.
For a hub holding many long-lived connections, getting any of these wrong (for example an unbounded per-connection outbound queue feeding a slow client) becomes a slow memory leak rather than a loud crash, which is harder to catch in testing.
Mitigate by treating connection-lifecycle management as a first-class, well-tested module with bounded outbound queues and explicit slow-client handling, not inline handler code.
Pin minor versions of the Tower and tower-http stack deliberately and review the changelog before any major bump, since that ecosystem occasionally lands coordinated breaking changes.

## 3. Database engine and data access: SQLite in WAL mode, via sqlx, behind a repository trait

### Decision

SQLite in WAL mode, embedded in the server process, accessed through sqlx with compile-time-checked queries.
Writes are funneled through a single serialized writer path; reads use a small read-only connection pool.
Migrations are plain, ordered SQL files run by sqlx's migrator.
All persistence sits behind a repository trait so the storage backend is a swappable implementation detail, with Postgres as the documented later target for the official instance if it ever outgrows single-writer SQLite.

### The disagreement and how I resolved it

The engine is unanimous: all three proposals chose embedded SQLite in WAL mode behind a swappable interface, and I adopt that without reservation.
For a handful of users the largest single lever on idle footprint is whether there is a second process at all, and an embedded engine removes an entire second process, its idle RAM floor, its own container, and its own backup and upgrade story that a friend-group admin would otherwise have to operate correctly.
SQLite is the mature option in that space, with well-understood indexing, a single durable file, a file format that has not broken compatibility in over two decades, and WAL mode giving concurrent readers alongside one writer, which is ample for this scale.
Postgres is the stronger engine for multi-writer concurrency and remains the right thing to swap in behind the repository trait if the official instance ever needs it, but as a default it reintroduces exactly the second-process weight the self-host requirement forbids, for concurrency advantages this scale will not use.
A repository trait keeps that swap real rather than aspirational, and it extends the same swappable-interface philosophy the owner already committed to for in-memory state.

The live disagreement is the data-access layer for Rust: the lean proposal chose rusqlite with a hand-built single-writer thread and a synchronous read path, arguing that wrapping an embedded file database in an async driver buys nothing because there is no network wait to overlap; the safe proposal chose sqlx for its compile-time-checked queries.
I resolve this for sqlx, and I fold in the lean proposal's correct insight rather than discarding it.

The lean proposal is technically right that async does not overlap real I/O for an embedded database, but that is not the benefit that decides it.
The benefit that decides it is that sqlx's query and query_as macros validate the literal SQL against the real schema at build time, so a refactor that breaks a query fails cargo build instead of a running self-hosted server.
That is the same compile-time-correctness property that justified choosing Rust in the first place, now applied to the persistence layer, and it is a durable maintainability asset over a decade of contributions.
Against that, the footprint delta between sqlx and hand-rolled rusqlite at a handful of users is negligible: both must move blocking SQLite work off the async worker threads, sqlx via its own worker mechanism and rusqlite via manual spawn_blocking, so the runtime shapes converge and the deciding difference is the compile-time query guarantee.

The lean proposal's real insight is that SQLite has exactly one writer, and a generic async pool sized for a networked database fights that model.
I honor it as a hard architectural rule rather than by picking a different library: writes are serialized through a single logical writer path behind the repository trait, and reads go through a separate small read-only WAL pool.
sqlx is configured to that shape, so it never pretends arbitrary concurrent writers are fine.
I also adopt the lean proposal's write-path discipline in full: high-frequency, low-durability events (typing indicators, presence, in-session Voice Canvas deltas) stay off the durable SQL write path entirely, reserving SQLite writes for durable chat history and periodic checkpoints, so the single writer never becomes a hot-path bottleneck.

A full ORM (Diesel or SeaORM) was rejected.
Diesel's compile-time story is even stronger than sqlx's, but its synchronous core forces a spawn_blocking bridge under an async server, which is itself a resource-exhaustion risk in a connection-heavy hub, and its natural Postgres default reintroduces the second-process problem.
Pure key-value stores (sled, redb) were rejected because the data here is genuinely relational and would require hand-rolling secondary indexing that SQLite already provides.

### Main risk and mitigation

Two risks.
First, SQLite serializes writes even in WAL mode, so if the official instance grows well past friend-group scale before a Postgres implementation of the repository trait is actually built, write latency and lock contention become a real ceiling.
Mitigate by defining the repository trait from day one, keeping write transactions short with a sane busy_timeout, keeping ephemeral high-frequency events off the durable path as above, and treating write-latency and lock-contention metrics as the explicit trigger to build the second storage implementation as a planned, mechanical swap rather than an emergency.
WAL mode also requires a filesystem that supports it correctly, which rules out some network-mounted data directories; document that plainly in the self-host guide.
Second, sqlx's compile-time checking is only as good as the offline query cache staying in sync with migrations, so enforce cache regeneration and a diff check as a CI step or the guarantee silently degrades to checking against a stale schema.

## 4. Event identity and total ordering: UUIDv7 identity plus a server-assigned per-scope monotonic sequence

### Decision

Every event (chat message, system event, admin action, and the same pattern later for Voice Canvas operations) carries two identifiers with two distinct jobs.
A UUIDv7 is generated at creation time, client-side where applicable, as the stable, globally unique identity: it lets the client optimistically render locally before the server acknowledges, and it doubles as an idempotency key on retry.
A strictly monotonic, per-scope, signed 64-bit sequence number is assigned by the server at commit time and persisted in the same transaction as the event; this sequence, not the UUID, is the authoritative total order and the sync cursor clients use to ask for everything after sequence N with no gaps and no duplicates.
Identity and sequence are modeled as distinct types, not both as bare integers or strings.

### The disagreement and how I resolved it

There is no disagreement to resolve: all three proposals independently converged on exactly this split, and all three reject the Snowflake-style bit-packed ID for the same reason.
I adopt the consensus and combine the mitigations each proposal contributed.

Identity and order are two problems, and collapsing them into one field does both badly.
Identity must be constructible by the client before any round trip, so optimistic local echo works and retries deduplicate; a server-only sequence cannot satisfy that because the client cannot know it until after a round trip.
UUIDv7 fits identity well: it is a standard 128-bit value generatable with no coordination, and its 48-bit millisecond timestamp prefix makes it sort approximately by time, which gives better SQLite B-tree index locality than random UUIDv4 and reduces write amplification on the small self-hosted disks this product targets.
Order must be a strict, gap-detectable total order within a scope, which a timestamp cannot give once two writers land in the same millisecond and which UUIDv7 only approximates; a client-generated value cannot be a trustworthy order key without reintroducing the distributed-uniqueness problem the single-process design exists to avoid.
Because owner decisions 4 and 7 make each deployment single-community and single-process, there is exactly one writer of record per scope, so a plain durable monotonic counter incremented inside the insert transaction is both sufficient and the simplest correct answer, with no worker-id allocation, no clock-skew handling, and no distributed coordination.
That sequence is what makes sync cheap and correct, and it serves the brief's own "efficient indexing" and "fast synchronization" goals directly.

The Snowflake-style single 64-bit ID packing timestamp, worker-id, and counter is the choice most people expect from a Discord-like product, and it is explicitly rejected.
Its entire value is letting multiple uncoordinated nodes mint conflict-free roughly-ordered IDs without talking to each other, a problem this architecture does not have by owner decision.
Adopting it now means either a worker-id field permanently hardcoded to zero, an unused knob every future contributor must understand for no benefit, or building real distributed worker-id allocation prematurely against the owner's explicit "add a backplane only when scale demands it."
It also conflates identity and order, which makes clean optimistic local echo harder.
If the official instance ever needs multiple writer nodes, the two-field scheme extends naturally by handing each node a reserved sub-range of the per-scope sequence, without redesigning identity.

### Main risk and mitigation

The sequence must be persisted durably in the same transaction as the event it orders, never merely held in memory and incremented, or a crash and restart can reuse or skip numbers in a way clients cannot reconcile against their local cache.
Keep "assign the next sequence for this scope" as its own repository-trait method distinct from ordinary reads and writes, so a future coordinator can be substituted at one seam if the single-writer assumption ever changes.
Because identity is only approximately time-sortable, any query or client path that orders history by identity instead of by sequence will silently misorder; add a lint or automated check asserting that every history and sync query orders explicitly by sequence.
A per-scope sequence has no meaning across scopes, so a future global activity feed spanning channels would need its own ordering answer; flag that if such a feature is ever proposed.

## 5. Wire format: schema-first JSON over HTTP and WebSocket

### Decision

JSON over both HTTP and WebSocket for the v1 control plane.
The contract is schema-first: a single source of record (OpenAPI for the REST resource surface, JSON Schema for the WebSocket event envelope and payloads) generates both the Dart client types and the Rust server types, and CI fails on any drift between the schema and the committed generated code.
The WebSocket event stream uses a small typed envelope: a discriminated type field, a protocol version, and the per-scope seq from section 4.
permessage-deflate is enabled on the WebSocket connection.
A compact binary encoding (MessagePack, or a purpose-built binary framing) is reserved as a documented, additive, per-message-type escape hatch for hot paths that measurement later proves need it.

### The disagreement and how I resolved it

This is the second real fork.
The lean and maintainable proposals both chose JSON; the safe proposal chose Protocol Buffers over WebSocket and HTTP with a single shared .proto, keeping JSON only for health, metrics, and admin.
I resolve it for JSON, and I deliberately absorb the safe proposal's strongest legitimate concern instead of waving it away.

The safe proposal's case for Protobuf rests on three real points: one schema of record giving cross-language compile-time type safety across the network boundary, a smaller and cheaper-to-parse binary encoding, and a field-number evolution model built for client and server versions that are not upgraded in lockstep, which is exactly the situation a self-hosted product lives in for years.
The third point is the strongest and I take it seriously, because self-hosted servers and official mobile clients genuinely will run a few versions apart.

Against Protobuf sit two costs the brief weights heavily.
It is not human-readable on the wire, so a self-hosting admin diagnosing a connection problem, or a contributor pasting a raw frame into an issue, cannot read it without a decoder, which cuts directly against "easy to self-host," "easy to contribute to," and "readable APIs."
And it requires a protoc codegen toolchain with per-language plugins on every contributor machine as a hard prerequisite, versus JSON's zero-toolchain baseline on both Dart (json_serializable and freezed) and Rust (serde).

What tips the decision is scope.
The Voice Canvas high-frequency operation stream, which is where a binary encoding's byte and parse-CPU savings would genuinely matter, is explicitly out of scope for this decision and is decided separately.
What remains here is the chat and control plane: text messages, presence, signaling, account, channel, invite, and admin operations, at ordinary message sizes and rates.
At that scale Protobuf's efficiency advantage over JSON is modest, and permessage-deflate closes most of the remaining gap because JSON's repetitive key structure compresses very well.
So the single strongest reason to pay Protobuf's debuggability and toolchain cost does not apply to the surface this decision actually covers, and where it does apply it can be adopted locally, in the out-of-scope canvas stream, without dictating the whole protocol.

I do not, however, accept the lean proposal's looser "just JSON with a reserved escape hatch" stance unmodified, because the safe proposal is right that ad-hoc JSON lets the two sides drift silently.
I adopt the maintainable proposal's schema-first discipline and then harden it with the safe proposal's schema-evolution rigor.
The JSON is generated from one schema of record for both Dart and Rust, CI regenerates and diffs on every change, and both ends run schema validation in tests, so drift is caught at merge time rather than in production.
To handle the version-skew concern that was Protobuf's best argument, the protocol is versioned in the envelope, unknown fields are ignored, changes are additive-only with a documented deprecation path, and CI runs a schema-compatibility check against the previous release.
This captures most of Protobuf's cross-language type safety and most of its graceful-skew behavior, while keeping frames readable off the wire and keeping the contributor toolchain empty.

gRPC specifically was not the safe proposal's choice, so its HTTP/2 reverse-proxy friction is not the deciding factor, but it is worth recording that plain JSON over ordinary HTTP and WebSocket also sidesteps that whole class of self-host proxy configuration pain, which reinforces the self-host-simplicity case.
MessagePack as the default was rejected for the same readability reason as Protobuf, since permessage-deflate already captures most of its byte saving on top of readable JSON.
Zero-copy binary formats (Cap'n Proto, FlatBuffers) solve a serialization-CPU problem the control plane does not have; that payoff belongs to the out-of-scope canvas stream.

### Main risk and mitigation

JSON's schema is enforced by convention and CI discipline, not by the wire format itself, so if someone hand-edits a generated Dart or Rust model out of step with the schema, or skips regeneration, the two sides can drift.
The mitigation is process, not format: CI regenerates both sides from the schema on every change and fails on any diff against committed generated code, both ends validate against the schema in tests, and the additive-only and compatibility-check rules above are enforced in CI, so a mishandled breaking change is caught before merge rather than discovered by a self-hoster on an old release.

## Deliberate divergences from a naive rebuild

The assignment forbids leaning on any prior project, and it asks where this stack intentionally departs from a "rebuild the old thing" or "reach for the default Discord-clone stack" reflex.
Each divergence below was reasoned from the brief and the owner decisions, and none of them draws on any existing toolchain or codebase.

- Embedded SQLite instead of a Postgres-by-default backend.
  A Discord-like backend reflexively reaches for a separate Postgres process; this stack rejects that as the default because a second process contradicts the extreme self-host lightness requirement, and keeps Postgres only as a later swap behind the repository trait for the official instance.
- Split identity and order instead of Snowflake IDs.
  The expected Discord-clone choice is a single Snowflake-style ID doing both jobs; this stack splits UUIDv7 identity from a per-scope monotonic sequence because the single-writer architecture makes Snowflake's distributed machinery permanent dead weight.
- Single process with a swappable interface instead of a message-queue backplane on day one.
  There is no Redis, no external broker, and no second service in v1; state lives behind an interface that can later be backed by a shared backplane only when scale actually demands it.
- Schema-first JSON instead of either ad-hoc JSON or a heavy binary RPC.
  Rather than the two reflexes of "just serialize whatever" or "adopt gRPC because it looks serious," this stack takes a deliberate middle path: readable JSON on the wire, but generated from one schema of record with CI-enforced cross-language type safety and version-skew rules.
- Rust chosen on structural grounds, decided independently.
  The language was chosen for its zero-GC idle footprint and its compile-time concurrency correctness on a shared-state realtime hub, weighed against Go's contributor-pool advantage on the merits, not because any prior project used any particular language.
- sqlx compile-time-checked queries with an explicit single-writer discipline instead of an ORM or an unconstrained pool.
  The persistence layer is deliberately shaped to SQLite's real one-writer concurrency model and verified at build time, rather than hidden behind an ORM's runtime query builder or a generic pool that pretends concurrent writers are free.

## How the choices reinforce each other

The five decisions were made independently but they compound into one coherent design.
Rust and Axum give a small, memory-safe, single static binary that starts fast and idles cheap, which is what the self-host requirement demands and what a realtime connection hub needs to be correct under concurrency.
Embedded SQLite in that same binary keeps a self-hosted deployment to one process and one file, and the repository trait keeps the door open to Postgres for the official instance without forking the codebase, consistent with the swappable-interface philosophy already chosen for runtime state.
sqlx ties the database layer's compile-time guarantees to the language's own, so "does this query match the schema" and "is this state safely shared across tasks" are both answered at the same cargo build.
The UUIDv7-plus-sequence scheme is the minimal, correct consequence of the single-process, single-community architecture, needing no distributed coordination because there is no distributed writer to coordinate.
Schema-first JSON carries typed contracts across the wire to the Flutter client while keeping every frame readable for the self-hoster and contributor, and it reserves a binary escape hatch for the measured hot paths and the out-of-scope canvas stream where density actually pays off.
The through-line is consistency: compile-time-checked types wherever the boundary allows, a single authoritative writer per scope, and readable, inspectable surfaces for the people who have to run and extend this server for years.
