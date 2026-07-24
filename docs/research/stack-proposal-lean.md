# Lean Server Stack Proposal

Status: pre-implementation research.
Scope: the main slim-m chat server only, not the push relay.
The push relay is a separate, already-decided service adapted from check-in-relay (Go), and is out of scope here.
The Voice Canvas wire format and coordinate handling are also out of scope, per the assignment.

## Optimization lens

This proposal answers five questions purely against one lens: minimize the self-hosted resource footprint.
Idle RAM, idle CPU, binary size, and cold start on a small box a friend group would run are the metrics that matter most.
Every choice below is justified from the brief and the owner's accepted decisions only.
No option was selected, rejected, or informed by any prior codebase, including echo-messenger, which was not consulted while writing this document.

Constraints treated as fixed inputs, not re-litigated here:
- One backend deployment is one community, so the data model and process model do not need multi-tenant isolation.
- The official instance is single-process, with state (including persistence) behind a swappable interface, and a shared backplane is added only if scale later demands it.
- Transport-only encryption for v1, with per-device keys pre-wired for later opt-in E2EE DMs, so the wire format and the server's plaintext access must both remain compatible with that later addition.
- The official instance and every self-hosted server run the same server image.

## Summary

| Question | Choice |
|---|---|
| Server language | Rust |
| Web and WebSocket framework | Axum (tokio and hyper) |
| Database engine | SQLite, WAL mode |
| Data access | rusqlite, single-writer thread plus a read-only connection pool, behind a repository trait |
| Event identity | UUIDv7 |
| Total ordering | server-assigned, per-scope, monotonic 64-bit sequence number |
| Wire format | JSON over HTTP and WebSocket, permessage-deflate enabled, MessagePack reserved as a documented escape hatch |

## 1. Server implementation language

### Choice: Rust.

### Rationale

A self-hosted server for a handful of users spends nearly all of its life idle, holding a small number of long-lived WebSocket connections open and doing almost no work.
The dominant cost in that state is not raw throughput, it is how much memory and how many periodic CPU wakeups the runtime itself needs just to exist.
Rust has no garbage collector, so there is no reserved GC heap headroom sitting on top of live data, and no background scan or scavenger thread waking the process on a timer while nothing is happening.
That directly serves the "idle CPU usage effectively zero" and "idle RAM" parts of the lens in a way that is structural, not tuned.
Rust also compiles to a single static binary with no bundled runtime or interpreter, which keeps binary size small and makes cold start close to instantaneous, since there is no VM boot or JIT warm-up before the process can accept its first connection.
The same binary can run tokio in single-threaded mode on a tiny self-hosted box and in multi-threaded mode on the official instance, so the resource profile scales down cleanly to the smallest deployment target instead of assuming a baseline the smallest box then has to pay for.
A long-lived process holding many concurrent connections in shared state is also exactly the shape of program where compile-time ownership and data-race checking earns its keep, catching a class of concurrency bug before it ever reaches a running self-hosted server that nobody is actively watching.

### Strongest alternative rejected: Go.

Go is the closest competitor on every axis in this lens.
It produces a single static binary, has fast cold start, simple concurrency primitives, and a noticeably gentler learning curve, which is a real point in its favor against the brief's own "easy to contribute to" goal.
It was rejected for this specific lens, and only this lens, because its garbage collector is a genuine, if modest, cost on exactly the two hardest axes here.
A GC-managed heap keeps some memory headroom beyond live objects, and Go's runtime scheduler wakes periodically even under zero load, which works against a target of effectively zero idle CPU.
Under bursty load, such as a suddenly busy voice channel's text and presence chatter, GC pauses can introduce latency jitter that an ownership-model language avoids by construction.
The gap between Go and Rust on absolute idle RSS for a small service is real but not dramatic, and this is the closest call in this whole proposal.
If contributor onboarding speed or compile-iteration time turn out to matter more in practice than this margin, Go is the fallback worth revisiting first.

Other languages were considered and rejected faster.
Any JIT or VM-based interpreted runtime, including Node, the JVM, or CPython, loses on all four axes simultaneously: interpreter or VM startup hurts cold start, JIT warm-up hurts steady-state CPU predictability, and baseline heap size is much larger than either Rust or Go before a single connection is served.
Zig or C would produce the smallest possible binaries with no runtime at all, but neither has a mature, battle-tested async HTTP, WebSocket, TLS, and SQLite stack today.
Building those foundations in-house for a server that handles authentication and user data is a correctness and security risk this project should not take on to chase a marginal binary-size win.

### Main risk

Rust's compile times and learning curve are real costs against the brief's "easy to contribute to" goal, and async Rust in particular has known sharp edges around trait bounds and pinning that can slow new contributors down.
Mitigate by keeping the async surface area small and conventional, favoring plain async functions over custom futures, and documenting the concurrency patterns used in the codebase rather than assuming familiarity.

## 2. Web and WebSocket framework

### Choice: Axum, on tokio and hyper.

### Rationale

The brief's split of request and response work from push and broadcast work maps cleanly onto REST for the former and WebSocket for the latter, and Axum supports both natively without pulling in a second framework.
Axum is built directly on tokio and hyper, maintained by the same team, which minimizes the risk of the framework and the async runtime drifting apart in a way that forces awkward version pinning later.
Its dependency footprint is opt-in through the tower middleware ecosystem, so a self-hosted build only pulls in the request tracing, compression, or rate-limiting layers it actually uses, rather than a fixed bundle of framework features that ship regardless of whether they are needed.
That composability matters directly for the lean lens: unused middleware is unused code in the binary and, in some cases, unused background work at runtime.
WebSocket upgrade handling is a first-class extractor in Axum, not a bolted-on extension, which keeps the connection-hub code close to the rest of the routing layer instead of split across two different libraries with two different conventions.

### Strongest alternative rejected: Actix-web.

Actix-web has a strong track record on raw throughput benchmarks and is a mature, production-proven choice.
It was rejected here because its performance advantage matters most at request volumes this deployment shape will not see, a self-hosted server for a handful of users is nowhere near the point where framework-level throughput differences are the bottleneck.
Actix-web's dependency graph and its actor-model heritage add conceptual and binary surface area that this project does not need, given both frameworks now sit on tokio underneath.
Axum's tighter, more composable middleware model is a better match for a project that wants to keep the base image lean and let self-hosters and the official instance opt into only what they use.

Hand-rolling routing and WebSocket handling directly on hyper was also considered and rejected, since it would mean reimplementing and maintaining routing, extraction, and connection-upgrade logic by hand, trading a small binary-size saving for a real, ongoing maintenance burden against a project that expects years of contributions.

### Main risk

The tower and tower-http ecosystem occasionally introduces breaking changes across major versions, which can force a coordinated upgrade across several dependencies at once.
Mitigate by pinning minor versions deliberately and reviewing the tower-http changelog before any major bump, rather than floating on the latest release automatically.

## 3. Database engine and data-access approach

### Choice: SQLite in WAL mode, accessed through rusqlite with a dedicated single-writer thread and a pool of read-only connections, hidden behind a repository trait.

### Rationale

For a handful of users, the single biggest lever on idle footprint is not the database engine's internal efficiency, it is whether there is a second server process at all.
An external database server, whatever engine it runs, means a second process to start, supervise, and keep warm, with its own idle RAM floor, its own container, and its own backup and upgrade story that a self-hoster now has to operate correctly.
An embedded engine that lives inside the same process as the application removes that second process entirely, which is a structural win on idle RAM, on operational complexity, and on the number of moving parts a friend-group admin has to reason about.
SQLite is the mature, battle-tested option in that space, with well-understood indexing, a single durable file, and WAL mode giving concurrent readers alongside a single writer, which is enough concurrency for a chat community at the scale this deployment targets.
SQLite has no network I/O of its own, it is local file and page-cache access, so wrapping it in an async database driver adds abstraction cost without buying anything a synchronous call does not already get, since there is no actual network wait to overlap with other work.
A dedicated writer thread that owns the one write connection and serializes writes through a channel matches SQLite's actual concurrency model directly, a single writer, rather than fighting it through a generic async connection pool sized for a networked database.
Read-only connections opened in WAL mode can be used directly from request handlers through a blocking-pool call, which keeps the common read path simple and fast without an async state machine wrapping a call that was never actually asynchronous.
Putting persistence behind a repository trait extends the same swappable-interface approach the owner already committed to for in-memory state on the official instance, applied here for the same reason, keep day one lightweight and defer scale-driven complexity to a swap only if it is actually needed.

### Strongest alternative rejected: PostgreSQL as the default self-hosted database.

Postgres is the stronger engine for write concurrency, complex joins, and multi-writer scalability, and remains a reasonable target to swap in behind the repository trait if the official instance later needs it.
It was rejected as the default for self-hosted deployments specifically because running it means running a second process, and that second process alone typically costs tens of megabytes of idle RAM before a single query runs, on top of its own connection pooling and backup requirements.
That directly contradicts the requirement that a self-hosted server for a handful of users stay extremely lightweight, for a scale of usage where Postgres's concurrency advantages are not the bottleneck anyway.
Keeping Postgres available only as a later swap for the official instance, rather than the default everyone pays for, matches the brief's own instruction to avoid premature complexity while still planning for growth.

A full ORM, such as Diesel or SeaORM, and an async SQL toolkit with compile-time query checking, such as sqlx, were also considered for the data-access layer.
Both are reasonable engineering choices in general, but both add abstraction weight, either a heavier query-builder runtime or an async wrapper around a resource that is not actually asynchronous, for a project whose data-access lens here is specifically about minimizing that overhead.
Pure key-value embedded stores, such as sled or redb, were rejected because the data here is genuinely relational, message history, channel membership, permissions, and would require hand-rolling secondary indexing that SQLite already provides.

### Main risk

A single writer thread is a real serialization point, if a self-hosted community grows unusually large, or if high-frequency ephemeral events end up routed through the same durable write path, that thread becomes the bottleneck.
Mitigate by keeping high-frequency, low-durability-need events, such as typing indicators, presence, and in-session Voice Canvas deltas, off the SQL write path entirely, reserving SQLite writes for durable chat history and periodic canvas state checkpoints.
WAL mode also requires a filesystem that supports it correctly, which rules out some network-mounted data directories, and that constraint needs to be documented plainly in the self-host deployment guide.

## 4. Event identity and total-ordering scheme

### Choice: UUIDv7 as the stable identity for every message and event, paired with a server-assigned, strictly monotonic 64-bit sequence number per ordering scope, such as a channel, a DM, or a Voice Canvas session.

### Rationale

Identity and ordering are two different problems and this proposal deliberately does not collapse them into one field.
Identity needs to be globally unique, generatable by the client before the server has seen the message at all, so an optimistic send can be deduplicated on retry, and reasonably compact on the wire and on disk.
UUIDv7 satisfies all three: it is a standard 128-bit identifier a client can generate locally with no coordination, and because it embeds a 48-bit millisecond timestamp prefix, it also sorts approximately by creation time for free, which gives better index locality than a fully random identifier like UUIDv4 when it sits in a SQLite B-tree, directly reducing index fragmentation and write amplification on the exact kind of small self-hosted disk this lens cares about.
Ordering needs a different property: a strict, gap-detectable total order within a scope, which a timestamp cannot reliably provide once two users write in the same millisecond, and which a UUID's embedded timestamp only approximates.
Because this architecture is single-process, with one writer thread per database by the database section above, assigning a strictly increasing integer sequence number is nearly free, it is an increment inside the same transaction as the insert, with no distributed coordination, no worker-id allocation, and no clock-skew handling required.
That sequence number is what makes sync cheap: a client asks for everything after the last sequence number it has seen, and a gap in that number is a reliable signal that something was missed, which a set of unordered UUIDs alone cannot give without a full diff.
This directly serves the brief's own "efficient indexing" and "fast synchronization" database goals.

### Strongest alternative rejected: a Snowflake-style composite identifier, packing a timestamp, a worker id, and a per-millisecond counter into one 64-bit integer, used as both identity and order.

This is the right tool for a problem this architecture does not have on day one.
Its entire value is letting many independent, uncoordinated nodes each generate conflict-free, roughly-sortable IDs without a shared counter, which matters when there are multiple writers.
This deployment has exactly one writer per database, by design, both because one backend deployment is one community and because the official instance is explicitly single-process for now.
Adopting a Snowflake scheme now means carrying worker-id allocation and clock-drift guards for a horizontal-scaling payoff that the owner's own decision explicitly defers until scale actually demands it.
If the official instance ever does need multiple writer nodes, the two-field approach chosen here extends naturally, by handing each node a reserved sub-range of the per-scope sequence, without having to redesign identity from scratch.

Plain timestamp ordering with no sequence number, and UUIDv4 identity with no separate ordering field, were both considered and rejected faster, for the same underlying reason: neither gives a deterministic, gap-detectable order under concurrent writers, which sync correctness depends on.

### Main risk

Carrying two fields, an opaque identity and a separate sequence number, means any query or client code path that orders by identity instead of by sequence will silently misorder history, since UUIDv7's time-sortability is only approximate, not exact.
Mitigate with a lint or a small automated check over the codebase asserting that every history or sync query orders explicitly by sequence, never by identity.
A per-scope sequence also has no meaning across scopes, so a future global activity feed spanning multiple channels would need its own ordering answer, which is fine, since no such feature exists yet, but should be flagged again if one is proposed.

## 5. Client-server wire format

### Choice: JSON over both HTTP and WebSocket, with permessage-deflate compression enabled on the WebSocket connection, and MessagePack reserved as a documented, additive escape hatch for specific high-frequency message types if measurement later shows it is needed.

### Rationale

The brief asks for efficient network usage and battery impact to be treated as first-class, and it also asks, independently, for readable APIs and for the project to be easy to contribute to, and those two goals are genuinely in tension for a wire format, so this choice tries to satisfy both rather than picking one and ignoring the other.
JSON requires no schema compiler or generated-code step on either side of the connection, the Flutter side already expects to generate JSON (de)serialization code as part of its normal tooling, and the Rust side's JSON handling is mature and fast.
That keeps the barrier to entry for a new contributor low, and it keeps the protocol debuggable in the exact situation where debuggability matters most, a self-hosting admin diagnosing a connection problem with a browser's devtools or a raw WebSocket inspector, with no decoder required to read a frame.
JSON's real cost is field-name repetition and text-encoded values, and that cost is substantially addressed by permessage-deflate, a standard WebSocket extension already implemented on both the Rust WebSocket stack and Flutter's WebSocket client, which is especially effective on JSON's repetitive structure and requires no codec change on either side.
Reserving a compact binary format as an additive, per-message-type upgrade, rather than a wholesale rewrite, means the protocol can move specific hot paths to something denser later without breaking or re-versioning the whole wire format at once.

### Strongest alternative rejected: Protobuf, with or without gRPC.

Protobuf gives real, measurable savings in bytes on the wire over JSON, and was the most seriously considered alternative.
It was rejected as the v1 default for two independent reasons.
First, it requires a schema compiler and a generated-code build step on both the Rust and Dart sides, which is a real tax on every contributor for every schema change, working against the brief's own "easy to contribute to" goal.
Second, and specific to this project's self-hosting story, it is materially harder to debug in the field, an admin troubleshooting a connection problem cannot read a raw frame without a decoder, where a JSON frame is readable as-is.
gRPC specifically also has weak or unofficial browser ergonomics, a mismatch for a project that may add a web client later, and its RPC framing solves a problem, service-to-service call semantics, that a WebSocket-push-heavy chat protocol does not primarily have.
Protobuf's binary-size advantage over JSON with compression is real but modest at the size of an ordinary chat message, and not worth the tooling and debuggability cost at this stage.

MessagePack as the default, rather than a reserved escape hatch, was also considered and rejected for the same debuggability reason, it is schema-free and simple to adopt, but it still trades away raw-frame readability for a network saving that permessage-deflate already captures most of on top of plain JSON.
Zero-copy binary formats such as Cap'n Proto or FlatBuffers were rejected as solving a serialization-CPU problem this application does not have at ordinary chat-message rates, that payoff belongs to the Voice Canvas's high-frequency transform stream, which is explicitly out of scope for this proposal.

### Main risk

JSON with compression still loses to a binary format on both bytes-per-message and parse CPU at very high fan-out, such as presence or typing chatter in a large voice channel, and on a small self-hosted box that CPU cost is not free.
If a future measurement shows this is an actual bottleneck rather than a theoretical one, migrate the specific hot message types to MessagePack using the reserved escape hatch, rather than treating it as a reason to abandon JSON's debuggability benefit up front, which would be optimizing before the brief's own evidence bar is met.
