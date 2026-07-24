# 0002 - Architecture follow-up decisions

Status: accepted.
Date: 2026-07-23.

These three decisions followed the echo-free re-derivation of the foundational architecture (see the fresh [STRATEGY.md](../STRATEGY.md) and the stack rationale in [research/stack-decision.md](../research/stack-decision.md)).
The owner was asked because the re-derivation changed or exposed choices worth confirming.

## 1. Database engine

Decision: embedded SQLite in WAL mode, one file inside the server process, accessed via sqlx with compile-time-checked queries and a single serialized writer path, all behind a repository trait.
PostgreSQL is kept only as a documented later swap for a single community that genuinely outgrows one process.
This confirms the fresh recommendation and reverses the first pass, which had defaulted to PostgreSQL for every instance.
Rationale: the brief's top priority is a lightweight, cheap self-host, and the single largest idle-footprint lever is removing a second process entirely; SQLite's single-writer model matches the app's own serialized-writer concurrency rather than fighting it.
Accepted risk: SQLite serializes writes, so a community growing far past friend-group scale before the Postgres implementation exists would hit a write-latency ceiling; write-latency and lock-contention metrics are the explicit trigger to build the Postgres swap.

## 2. Direct message scope

Decision: in v1, direct messages work only between users on the same deployment.
This confirms the recommendation and is a direct consequence of one-deployment-one-community plus the per-scope single-writer model, which presumes both participants' accounts live in one deployment.
Cross-deployment DMs (DMing someone on a different self-hosted server, or an official-instance user from a self-host) are effectively federation, a distinct distributed-systems design, and are out of scope for v1.
This is recorded so it is a deliberate scope decision rather than a surprise, and revisiting it later is separate work, not an extension of this architecture.

## 3. Presence privacy

Decision: presence (online status) is broadcast to shared-scope co-members by default, but v1 includes a hide-online-status option so a user can appear offline or invisible.
This changes the plan, which had presence broadcast with no opt-out in v1.
Rationale: online status is the same kind of privacy surface as read receipts, which were deferred for privacy, so presence gets a consistent user control from v1.
The hide option is a small addition (a presence-filtering rule plus a settings toggle) and does not affect the presence transport design.
