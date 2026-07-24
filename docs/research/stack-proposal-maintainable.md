# Server stack proposal: maintainability and contributor-pool lens

## Purpose and scope

This document proposes the foundational server stack for slim-m: the backend that a Flutter client (iOS and Linux first, Android next) talks to for text messaging, voice signaling, and screen share coordination.
It covers the core client-server backend only.
The Voice Canvas region, the push relay derived from check-in-relay, and the Flutter client itself are out of scope for this pass.

The optimization lens for this proposal is explicit: maximize long-term maintainability and the size of the realistic open-source contributor pool.
That means ecosystem maturity, approachability to new contributors, and operational simplicity are weighted above raw throughput or the theoretically fastest option.
Where a faster or more "serious" choice was available, it is named as the rejected alternative and the tradeoff is stated honestly.

Every decision below honors the brief and the owner's ten accepted decisions, in particular: transport-only encryption for v1, one backend deployment equals one community, the official instance is single-process with state behind a swappable interface, self-hosted account recovery is admin-issued codes only, and read receipts do not fan out to other users in v1.
No reasoning here relies on "an existing project already does this" or on the structure of any off-limits reference.
Each choice is justified from the brief and from the properties of the option itself.

## Summary

| Question | Choice |
|---|---|
| Server language | Go |
| Web and WebSocket framework | Go standard library `net/http`, plus `chi` for routing and middleware, plus `coder/websocket` for the realtime channel |
| Database engine and data access | SQLite (pure-Go driver), accessed through `sqlc`-generated queries behind repository interfaces, `goose` migrations |
| Event identity and ordering | UUIDv7 for global event identity, a per-scope monotonic sequence assigned by the single authoritative process for total order and sync cursors |
| Client-server wire format | JSON over HTTP and WebSocket, with an OpenAPI/JSON Schema contract as the codegen source of truth for both Dart and Go |

## 1. Server implementation language

### Choice: Go

### Rationale

The brief asks for a server that is cross-platform, Docker-deployable, and extremely lightweight for a self-hosted handful of users, while the brief and this lens both call for a large, approachable, long-lived contributor base.
Go serves both goals from the same properties rather than trading one for the other.

Go compiles to a single static binary with no runtime to install, which makes the Docker image trivial to build small and fast to start, directly serving "extremely lightweight" self-hosting and "fast startup time" from the brief's core principles.
The language is deliberately small: there is one obvious way to write a loop, one formatter (`gofmt`) that removes almost all style debate, and a standard library that already covers HTTP, TLS, JSON, and structured concurrency without third-party dependencies.
For a project that expects contributions from many different people over many years, a small, opinionated language with an enforced formatter measurably lowers the cost of a first pull request and keeps a decade of accumulated code looking like it was written by one disciplined team, which is exactly the "avoid a giant monolithic codebase" and "componentized architecture" goals in the brief.
Goroutines and channels map naturally onto the actual problem shape here, a server holding many long-lived WebSocket connections and fanning out events to them, without needing an external actor framework or a callback-heavy event loop.
Go's backend-focused contributor pool is large and specifically skewed toward the kind of engineer who wants to work on infrastructure and networking code, which is the profile this project needs most.

### Strongest alternative rejected: TypeScript on Node.js

TypeScript on Node.js has the single largest contributor pool of any option considered, and many Flutter/Dart developers already read JavaScript comfortably, so it is a genuine contender under this lens.
It was rejected for two first-principles reasons rather than because of unfamiliarity.
First, npm's dependency graph is a real long-term maintenance liability for a project that wants to stay small and auditable: transitive dependency counts balloon quickly, supply-chain incidents are a recurring category of npm-specific risk, and keeping a chat server's dependency tree trustworthy over many years is itself an ongoing maintenance cost that Go's much smaller, mostly-stdlib dependency footprint avoids.
Second, Node's runtime and V8 heap overhead sits well above a compiled static binary for the same workload, which cuts directly against "a self-hosted server for a handful of users must stay extremely lightweight," and its packaging story for a minimal Docker image (`node_modules`, lockfiles, bundler choice) is more moving parts than a single Go binary.

### Main risk

Go's error handling is explicit and repetitive (`if err != nil` at every call site), and the ecosystem deliberately avoids "batteries included" frameworks, so architectural decisions that a Rails- or Phoenix-style framework would make for free (project layout, admin scaffolding, validation conventions) are left to this project to define and document.
If the initial architecture and contribution guide are not written down clearly, that freedom can turn into inconsistent patterns across packages as more contributors join.
This is mitigated by writing the repository layout and package boundaries down early, not by picking a different language.

## 2. Web and WebSocket framework

### Choice: standard library `net/http`, `chi` for routing and middleware, `coder/websocket` for the realtime channel

### Rationale

The brief needs two things from this layer: a conventional JSON/HTTP surface for account, channel, invite, and admin operations, and a persistent WebSocket channel for realtime message and presence delivery.
Neither needs a full application framework; both are well served by Go's standard `net/http`, which already handles routing basics, TLS termination, and request/response plumbing without a third-party dependency to track for security patches or breaking releases.
`chi` is added on top purely for ergonomic sub-routing and a composable middleware chain (auth, logging, panic recovery, request IDs); it is explicitly designed as a companion to `net/http`, not a replacement, so its handlers are ordinary `net/http` handlers and nothing about the codebase becomes framework-specific.
That matters for approachability: a contributor who already knows Go's standard HTTP idioms is immediately productive, rather than needing to first learn a framework's own request/context types and conventions.
For the WebSocket layer, `coder/websocket` (the actively maintained successor to `nhooyr.io/websocket`) is preferred for its small, context-aware API surface, native `context.Context` cancellation, and clean integration with `net/http`'s connection hijacking, all of which keep the realtime code readable and easy to reason about for someone new to the codebase.
Staying close to the standard library minimizes the number of things a long-term maintainer has to track for upstream breakage, deprecation, or a maintainer walking away, which is the operational-simplicity half of this lens.

### Strongest alternative rejected: Gin

Gin is the most widely known Go web framework, with the largest tutorial base and the deepest familiarity among backend engineers who know only one Go framework, which makes it a legitimate rival on the "approachability" axis specifically.
It was rejected because it introduces its own context type and rendering/binding conventions that diverge from plain `net/http`, so contributions become tied to Gin's idioms rather than to Go's, and because a JSON-plus-WebSocket service does not need Gin's binding, rendering, or grouping machinery to begin with.
Adopting it would trade a small ergonomics gain today for a permanent framework dependency and a codebase that reads less like idiomatic Go to a newcomer who only knows the standard library.

### Main risk

Go's WebSocket library landscape has been unstable before: `gorilla/websocket`, the long-time default, was briefly archived in 2022 before a community team picked up maintenance, which is a reminder that even popular Go libraries can lose their maintainer.
`coder/websocket` is well-regarded and used in production by its backing company, but it is maintained by a smaller team than the wider Go ecosystem, so a similar stewardship gap is possible.
The mitigation is architectural: the WebSocket handling is isolated behind a small internal interface so the underlying library could be swapped with a bounded, well-scoped change rather than a rewrite.

## 3. Database engine and data access approach

### Choice: SQLite as the single database engine, accessed through `sqlc`-generated typed queries behind repository interfaces, with `goose` for plain-SQL migrations

### Rationale

Owner decision 7 fixes the official instance as single-process with state behind a swappable interface, and the brief demands that a self-hosted server for a handful of users stay extremely lightweight and that deployment be as simple as possible.
Both constraints point at the same answer: an embedded database that ships inside the one binary, needs no separate process, no network hop, and no second container to patch, back up, or upgrade.
SQLite is also arguably the most deployed and most stable database engine in existence, with a file format and SQL dialect that has not broken backward compatibility in over two decades, which is about as strong an "ecosystem maturity" signal as a database can offer for a project meant to last many years.
Because it needs zero external services, a new contributor can clone the repository and run the whole server locally with a single command and no `docker-compose up postgres` step first, which is a direct, measurable reduction in the barrier to a first contribution, one of the strongest levers on growing an open-source contributor pool.
Using a pure-Go SQLite driver (`modernc.org/sqlite`, a CGO-free transpilation of the SQLite C source) rather than a CGO-based driver keeps the static-binary, trivial-cross-compilation property that motivated the language choice in section 1 intact; a CGO dependency here would quietly reintroduce a C toolchain requirement into every build and every contributor's environment.
For data access, plain SQL files processed by `sqlc` are preferred over an ORM: `sqlc` generates fully typed Go functions from real, reviewable SQL at build time, with no runtime reflection and no query-building DSL to learn, so the actual query a reviewer approves is the actual query that runs, which serves both "efficient database queries" and "readable APIs" from the brief directly.
`goose` migrations are plain, ordered SQL files rather than a code-based migration DSL, for the same transparency reason.
Every store (users, channels, messages, invites, and so on) is accessed through a small Go interface, which is what makes the "swappable interface" owner decision real rather than aspirational: the domain and service layers depend on the interface, not on SQLite, so a future engine can be introduced later without touching call sites.

### Strongest alternative rejected: PostgreSQL as the default engine

PostgreSQL is the mainstream "serious backend" default, with genuine strengths this proposal gives up: true concurrent multi-writer access instead of SQLite's single-writer-at-a-time model, a richer native type system, and a well-worn horizontal-scaling and replication story.
It was rejected as the default specifically because it fails the self-host lightweightness requirement: it is a second long-running process with its own memory footprint, its own upgrade and backup discipline (major version upgrades, `pg_dump` or WAL-based backup, connection pooling), and its own operational learning curve, all of which raise the bar for the friend-group operator the brief targets and, by extension, shrink the pool of people who will ever run the project at all, let alone contribute to it.
Requiring it for local development would also mean every contributor needs a database service running before they can execute the test suite, which is friction this proposal deliberately avoids.

### Main risk

SQLite serializes writes even in WAL mode, so if the official hosted instance's community count grows well past friend-group scale before a Postgres (or otherwise multi-writer) implementation of the storage interface actually gets built, write latency and lock contention become a real bottleneck.
This is a genuine and known limit of the choice, not a hidden one.
It is mitigated by defining the repository interfaces from day one rather than retrofitting them later, and by watching write-latency and lock-contention metrics as an explicit trigger for building the second storage implementation, so the swap is a planned, mechanical exercise rather than an emergency rewrite.

## 4. Event identity and total-ordering scheme

### Choice: UUIDv7 for event identity, a per-scope monotonic sequence assigned by the single authoritative process for total order and sync cursors

### Rationale

Owner decisions 4 and 7 together mean that in v1 there is exactly one writer of record for any given community: one backend deployment per community, running as a single process.
That is a much easier ordering problem than a distributed system's, and the ordering scheme should not pay for a problem this project does not have.
Two distinct needs exist here and they are best served by two different primitives rather than one primitive doing both jobs badly.
The first need is a globally unique, stable identity for every event (message, channel event, admin action) that can be generated offline on the client before the server has acknowledged it, so a client can compose a message while disconnected and reconcile it deterministically on reconnect.
UUIDv7 (standardized in RFC 9562, published 2024) fits this well: it is globally unique, roughly time-ordered which keeps database index locality reasonable, generatable on either the client or the server with no coordination, and it is the form the wider ecosystem is actively consolidating around, meaning growing native support in databases, ORMs, and client libraries including Dart's `uuid` package.
The second need is a strict, gapless total order within a given scope (a channel, a DM, a canvas region) that clients can use as a sync cursor, "give me everything after sequence N."
UUIDv7 is not sufficient for this on its own: it gives approximate time ordering but is not guaranteed strictly monotonic across implementations, especially for multiple events generated within the same millisecond, so it is an identity, not an order index.
Because there is a single authoritative process per community, a simple per-scope monotonic integer counter, assigned only at server commit time, gives a strict total order and a trivially efficient, gap-detectable, perfectly index-friendly sync cursor, at essentially zero implementation cost, precisely because no distributed coordination is required to assign it.

### Strongest alternative rejected: Snowflake-style bit-packed IDs

The Discord/Twitter-style 64-bit ID (timestamp bits, worker-id bits, sequence bits packed into one integer) is the option most people expect from a Discord-like product, and it is a reasonable design for a system with multiple concurrent ID-generating nodes.
It was rejected because slim-m does not have that problem in v1: owner decision 7 explicitly commits to a single process, so a worker-id field would either sit permanently hardcoded at zero, an unused knob every future contributor has to understand for no benefit, or the project would need to build real distributed worker-id allocation prematurely, directly contradicting the owner's own "add a shared backplane only when scale actually demands it."
Snowflake layouts are also bespoke per company with no single standard, so a new contributor has to learn slim-m's specific bit-packing choices rather than reading a public specification, which is a small but real approachability cost against the standardized alternative.

### Main risk

The per-scope monotonic counter is a clean simplification precisely because it assumes a single writer, and that assumption is the exact thing owner decision 7 leaves open to change later if the official instance ever needs a shared backplane.
If that day comes, sequence assignment needs a single serialization point per scope again, or a different ordering primitive such as a hybrid logical clock, and that is a real migration, not a configuration flip.
The mitigation is to keep sequence assignment behind the same storage interface boundary as section 3, and to treat "assign the next sequence number" as its own interface method distinct from ordinary storage reads and writes, so a future coordinator can be substituted at one seam instead of at every call site that touches ordering.

## 5. Client-server wire format

### Choice: JSON over HTTP and WebSocket, with an OpenAPI and JSON Schema contract as the shared codegen source of truth for Dart and Go

### Rationale

The realistic message sizes in a text-and-signaling chat application are small, so the bandwidth and CPU savings a binary format offers matter far less here than they would to a raw-performance-optimized pass, and this pass is explicitly optimizing for maintainability and contributor approachability instead.
Under that lens JSON's properties are close to strictly better for this project: it needs no codegen toolchain to get started, it is natively supported on both ends (Dart's `dart:convert` plus the mature `json_serializable`/`freezed` codegen pattern already standard in the Flutter community, and Go's standard `encoding/json`), and, most importantly for a volunteer-driven open-source project, it is human-readable on the wire.
A contributor can `curl` an endpoint, open a browser's network inspector, or paste a raw WebSocket frame into a GitHub issue, and every other contributor can read it immediately without a schema decoder.
That transparency is a real, ongoing maintainability property: it lowers the cost of diagnosing a bug report from a self-hoster who has no way to run a binary-format decoder, and it keeps the "operational simplicity" bar low for the exact audience this project is trying to grow.
To avoid JSON's lack of an enforced schema turning into client/server drift, the contract itself is still schema-first: the REST-shaped resource API (accounts, channels, invites, admin) is defined in OpenAPI and used to generate both the Dart client models and Go server-side request/response types and validation, and the WebSocket event stream uses a small typed envelope (a discriminated `type` field plus a per-scope `seq` from section 4) with its payload shapes defined the same way.
This gets most of a binary schema format's compile-time safety on both ends of the wire without paying for opaque bytes or a mandatory binary codegen toolchain.

### Strongest alternative rejected: Protocol Buffers over gRPC (or Connect)

Protobuf-based RPC is the mainstream "serious contract-first API" choice and was the closest competitor here: a single `.proto` source of truth, smaller and faster-to-parse payloads, and a mature, Google-backed toolchain with genuine ecosystem maturity.
It was rejected for this lens on four grounds.
The binary wire format is not human-debuggable without tooling, which directly raises the triage burden for an all-volunteer contributor base and for self-hosters who like to inspect their own traffic.
gRPC's HTTP/2-only transport adds real reverse-proxy configuration complexity for self-hosters running behind common front doors like Caddy, Traefik, or nginx, a well-documented source of "why doesn't streaming work" support burden in other self-hosted open-source projects, which directly works against the operational-simplicity goal for the audience this project depends on for its contributor funnel.
It requires a codegen toolchain (`protoc` plus per-language plugins) on every contributor's machine as a hard prerequisite, versus JSON's zero-toolchain baseline.
And the bandwidth and parse-speed advantages it offers matter far more to a performance-first pass than to a text-chat control plane at the message sizes this product actually produces.

### Main risk

JSON's schema is enforced only by convention and CI discipline, not by the wire format itself, so if the OpenAPI/JSON Schema contract is not kept as the actual generation source, meaning someone hand-edits a Dart or Go model out of step with the schema, or skips regenerating after a schema change, the client and server can silently drift apart.
The mitigation is process, not format: CI regenerates both the Dart and Go code from the schema on every change and fails the build on any diff against committed generated code, and both ends run schema validation in tests, so drift is caught at merge time rather than discovered in production.

## How these choices reinforce each other

The five decisions were made independently but they compound.
Choosing Go for the static-binary property is what makes SQLite's zero-extra-process property fully realized rather than partially undone by a CGO toolchain requirement, which is why the pure-Go SQLite driver specifically was called out rather than the more common CGO-based one.
Choosing a single-process authority for v1, an owner decision rather than an architectural choice made here, is what makes the simple monotonic-sequence ordering scheme correct and sufficient rather than a shortcut that will need patching soon.
And staying close to standard, inspectable formats at every layer, a small language close to its standard library, a web layer close to `net/http`, a database with no separate service, and a wire format anyone can read off the network, adds up to a server that a new contributor can clone, run, and start reading in one sitting, which is the actual goal of this pass.
