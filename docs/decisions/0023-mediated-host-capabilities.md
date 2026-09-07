# 0023 - Mediated host capabilities

Status: proposed (design only; the capability-granting surface is not built by this record)
Date: 2026-09-07

## The ask

A module today is pure compute: it receives an input and returns an output and can reach nothing else (decision 0021's sandbox, decision 0022's "no ambient authority").
That is enough for commands, code-block runners, slash commands, scenes and in-chat games.
It is not enough for the classes decision 0022 named as the deferred frontier: a module that posts a message on its own, remembers something between calls, or reacts to an event (the streamer's-corner surface).

This record designs the one foundation those classes share - **mediated host capabilities**: specific, capability-gated calls the host lets a module make, and (later) events the host pushes to a module.
It does not build that surface.
It fixes the contract so the build, when it happens, is a bounded, reviewable addition rather than a hole.

## The principle it must not break

Decision 0021's security model is the constraint every choice here serves:

- **No ambient authority.** A module gets exactly the capabilities its manifest declared and an admin approved, nothing else. Everything else stays default-deny.
- **The sandbox boundary is the design.** A module still cannot touch slim's memory, the database, the filesystem, or the network. A capability is not a hole in the sandbox; it is a narrow, named door the host opens, validates, and walks through on the module's behalf.
- **Each capability carries its own security review.** The isolation that makes a scene safe is not the isolation a host call needs (decision 0022's guardrail). `kv.store` and `message.post` are separate reviews, separately shippable.
- **Off by default, per space, reversible, audited.** A capability does nothing until it is declared, approved at install, enabled, and (where relevant) the caller holds the permission - and every grant is on the existing moderation-audit trail.

## The host-import ABI

ABI v1 is import-free: a module imports nothing, and the host refuses to instantiate one that imports anything (decision 0021).
That refusal is exactly what makes the sandbox easy to reason about, so it is not relaxed generally.
Instead, a module that wants a capability imports **exactly one** host function, from a single reserved namespace:

```wat
(import "slim" "host_call" (func (param i32 i32) (result i64)))
```

- `host_call(req_ptr: i32, req_len: i32) -> i64` - the module writes a UTF-8 JSON request at `req_ptr`/`req_len` and calls this; the host returns a packed `(resp_ptr << 32) | resp_len` pointing at a UTF-8 JSON response.
- The host writes the response **into the module's own memory** using the module's existing `alloc` export - the same mechanism `run` already uses in reverse - so no new export is required and the response lives in the module's address space, not the host's.

The import policy becomes: **a module may import nothing, or exactly `slim.host_call` and nothing else.**
Any other import, and more than the one, is still refused outright.
`slim.host_call` is honoured only when the module's manifest declares at least one capability and the capability surface is enabled (see [Guardrails](#guardrails)); otherwise even that import is refused, so a stock deployment behaves exactly as it does today.

This is a deliberate evolution of the execution contract, not a silent one.
Pure modules stay on the import-free contract unchanged; a capability-using module opts into the one-import contract, and the host's acceptance of it is gated.

### The request and response

The request names the capability and its arguments:

```json
{ "capability": "kv.store", "op": "set", "key": "score", "value": "42" }
```

The response is the same `{ok}` shape the command protocol already uses:

```json
{ "ok": true, "value": "42" }
{ "ok": false, "error": "quota exceeded" }
```

A host-level refusal (capability not declared, not approved, not permitted, malformed request, quota hit) is an `{ok: false, error}` returned to the module - never a trap and never a leak of anything outside the module.
The host validates every field; the module is never trusted to have sent a well-formed or authorized request.

### The call context

A `host_call` runs inside a known context the host establishes before it ever calls `run`: **which module, which space, which invoking user, which channel.**
The module cannot set or spoof any of these - they come from the request that reached slim, not from the wasm.
So a capability that acts on the user's behalf (posting a message) posts as that user in that channel, and a capability's permission check is evaluated against that user, in that channel, exactly as any other action is.

## Capability gating

Three independent gates, all of which must pass, before `host_call` does anything:

1. **Declared.** The capability string is in the module's manifest `capabilities`.
2. **Approved.** It is in the space's approved-capability set for this module, recorded at install (the `approved_capabilities` slot decision 0021 already stores).
3. **Permitted.** For a capability that acts in a channel or on a user's behalf, the invoking user holds the permission that action requires, evaluated in that channel - the same gate the equivalent first-party action uses. A capability that is purely the module's own (per-module storage) needs only 1 and 2.

A capability also carries its own **resource bounds**, enforced by the host, independent of the module's compute limits: how much it may store, how many calls per run, how large a payload. These are part of each capability's own review, not a global setting.

## Reactive execution (host-to-module events)

The streamer's-corner class needs the other half: the host pushing an event to a module that runs reactively, not only answering a user's request.
This record fixes the shape and defers the build.

- A module declares an `event-handler` extension point naming the host event it wants (a versioned event kind) and the capability it needs to respond.
- The host invokes a dedicated export - `on_event(ptr, len) -> i64`, the same calling convention as `run` - with the event payload, in a host-established context, under the same fuel/wall/memory limits.
- What the handler may do is exactly what its declared, approved capabilities allow; a handler with none can compute but not act, which is useless, so a reactive module is by definition a capability-using one.

Reactive execution is a later sub-phase than the request-driven `host_call` above, because it also needs a scheduling and back-pressure model (a flood of events must not become a flood of module runs); that model is out of scope here.

## The reference capability: `kv.store`

The first capability to build, because it is the safest: it touches nothing but the module's own bounded storage.

- **Scope.** A key-value store private to `(space, module)`. No module can read or write another's, and it never leaves the space.
- **Operations.** `get`, `set`, `delete`, `list` (keys only, paginated).
- **Bounds** (host-enforced, part of its review): a max key length, a max value size, a max total entries and total bytes per `(space, module)`, and a per-run call cap. Over any bound is a clean `{ok:false,error}`, never a partial write.
- **Gating.** Declared + approved only; no permission gate, because it is the module's own data and acts on no channel and no other user.
- **Lifecycle.** A module's store is dropped when the module is uninstalled from the space, the same way its permissions and grants are.

`kv.store` deliberately has no way to observe or affect anything outside the module, which is what makes it the right first proof of the whole surface.
`message.post` is the obvious second capability and is a larger review - it acts in a channel as a user, so it needs the permission gate, rate limiting, and a careful answer to "posts as whom" - and is not part of this record's build.

### Persistence and the sync/async boundary

The scaffolded `kv.store` splits into two halves along a deliberate seam.
The capability's *shape* - its four operations, its per-request and per-store bounds, and its isolation between modules - is implemented against a `KvBackend` trait and proven end to end in memory, because that is the part a security review actually needs to judge, and it is judgeable without deciding how the bytes persist.
*Where the bytes live* is the durable `KvBackend` an owner decides on, and it is left open on purpose, because it is a real architectural fork rather than a detail:

- `slim.host_call` is a **synchronous** wasm host function (wasmi has no async), running on a `spawn_blocking` thread, while slim's store is **async** sqlx. A durable backend must bridge that. The two candidates are (a) a backend that `block_on`s the async store from the blocking thread - simple, but it holds a database round trip inside the module run, per call; or (b) an **effects model** - load the module's `kv` snapshot before the run, serve reads and buffer writes in memory during it, and apply the buffered writes after `run` returns - which keeps the run itself free of database I/O and makes every effect reviewable in one place, at the cost of a snapshot per run.
- Either way the schema is small: `module_kv(module_id, key, value)` (a `space_id` column is trivial to add when slim gains more than one space; today it has one), with the entry and byte caps enforced on write.
- The `KvBackend` trait is exactly the seam that keeps this open: `module_runtime` depends on the trait, not on the store, so choosing (a) or (b) - or changing it later - never touches the gate or the capability logic.

This split is the reviewable decision this phase hands the owner: the gate and the capability are built and tested; the persistence backend is one trait implementation, and which one is a call to make deliberately, not one an autonomous change should have made.

### Threat model (kv.store)

What a hostile or buggy module could try, and why each fails closed:

- **Read or clobber another module's data.** Every operation is keyed by the host-established `module_id`, which the module cannot set or spoof; there is no operation that takes another module's id.
- **Exhaust host memory or disk.** Per-store caps (entries, total bytes) and per-request caps (key length, value size) bound the total; a per-run call budget bounds how much one run can attempt even within its fuel. Over any cap is a clean refusal, never a partial write.
- **Escape the sandbox through the response.** The host writes the response only through the module's own `alloc`, into the module's own memory; it never hands back a host pointer, and a failure to write is an empty response, not a host error.
- **Turn a bad request into a crash.** Every field is validated host-side; a malformed request, an unknown op, or a missing argument is a refusal, never a panic or a trap.
- **Do anything at all when it should not.** The capability runs only when the surface is on (owner flag), the module declared `kv.store`, and the space approved it; any gate failing is default-deny.

The one thing this threat model does not yet cover is the durable backend's own surface (a `block_on` starving the blocking pool, or a snapshot's size), which is part of that backend's separate review.

## Phasing

- **Phase A - this record.** The contract.
- **Phase B - the host-import surface, behind a feature flag, off by default.** The `slim.host_call` import wiring in the module host, a capability registry, and the declared/approved/permitted enforcement - with **no capability implemented**, so the only observable behaviour is that a capability-declaring module can be instantiated and its calls are all refused. Ships dark; proves the gate.
- **Phase C - `kv.store`.** The reference capability behind the same flag, with its bounds and its own security review.
- **Phase D - `message.post`.** Separate review; posts as the invoking user, permission-gated, rate-limited.
- **Phase E - reactive events.** `on_event`, the `event-handler` extension point, and the scheduling/back-pressure model.

Phases B and C are the capability-granting core.
They change the sandbox boundary, so they are reviewed and merged by the owner deliberately, never landed automatically.

## Guardrails

- **Flagged off by default.** Until the owner turns the capability surface on for a deployment, `slim.host_call` is refused exactly like any other import, and every module behaves as it does today. The flag is the master switch the whole surface hangs behind.
- **Default-deny at every gate.** An undeclared, unapproved, unpermitted, malformed, or over-bound call fails closed with a clean error. The failure path is the common path and is tested first.
- **One bounded contract at a time.** Each capability is added deliberately, with its own review and its own bounds, never by widening a generic hole. `host_call` is a dispatcher over a fixed, reviewed set of capabilities, not an escape hatch.
- **No new trust in the module.** Every value in a request is validated host-side; the context (space, user, channel) is host-established and unspoofable; a module error can never become a host error.

## What is built, and what is not

Phases B and C are now scaffolded, off by default, as owner-reviewed pull requests: the gated `slim.host_call` surface, and `kv.store`'s shape (operations, bounds, isolation) against a `KvBackend` trait with an in-memory reference, both proven end to end but reached by no live path.

Not built: reactive execution (Phase E), `message.post` (Phase D), and `kv.store`'s durable backend (see the persistence section - the deliberate fork left to the owner). The owner flag that would ever turn the surface on is also not built; until it is, `slim.host_call` is refused exactly like any other import.
