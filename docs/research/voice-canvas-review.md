# Voice Canvas Plan: Adversarial Review

Target document: `docs/research/voice-canvas.md`.
Cross-checked against `docs/BRIEF.md`, the sibling reports in `docs/research/`, the echo-messenger reference notes (`decentralized-chat-app/reference-echo-messenger.md`), and the `docs/voice-lounge/*` decision-of-record folder in `decentralized-chat-app`.

Severity key: critical findings would force a redesign of the plan as written.
Major findings are real defects that should block sign-off until addressed.
Minor findings are worth fixing but do not block the overall direction.

## Critical findings

### 1. The per-channel `seq` scheme is already contradicted by a sibling report, and for a good technical reason

`voice-canvas.md` recommends "a per-channel monotonic seq assigned in the same transaction as each write."
`database.md`, reconciling the same feature, explicitly overrides this: "`id` supersedes that report's separate per-channel `seq` counter... A snowflake ID is generated in-process with no database round trip and no shared counter, so concurrent writes to the same channel no longer serialize on ID allocation."

This is not a stylistic disagreement, it is a correctness and performance problem in the plan as written.
A monotonic counter that must be assigned "in the same transaction as each write" and stay gap-free per channel can only be implemented as a shared counter row that concurrent writers lock and increment (an approach close to `SELECT ... FOR UPDATE`).
That serializes every commit to a channel behind one row lock, which is the worst possible bottleneck precisely for the scenario the Voice Canvas exists to support: several people drawing in the same channel at once.
`realtime-sync.md` independently reaches the same conclusion from a different angle: it specifies a single global 64-bit snowflake ID space used as the ordering key for every persisted event including `canvas_op`, and a unified catch-up endpoint (`GET /api/sync?after=<last_id>&kinds=message,reaction,canvas_op`) that merges canvas ops chronologically with messages and reactions in one cursor scan.
A per-channel counter that restarts at 1 in every channel cannot be merged into that global cursor at all.

Two sibling specialist reports, working from different angles, both concluded the opposite of what this plan proposes.
The plan should adopt the global snowflake ID as the canvas seq, dropping the per-channel counter entirely, or explicitly justify why canvas needs a separate ordering scheme and how it interoperates with the unified sync endpoint the rest of the system depends on.

### 2. Canvas content privacy is never addressed, even though the reference material this report cites resolves it

`voice-canvas.md` treats the `canvas_ops` log as an unconditional moderation audit trail ("who drew what, when") and never once mentions encryption, `is_encrypted`, or any privacy boundary for canvas content.
The echo-messenger decision record this report is explicitly built from (`04-encrypted-canvas.md`, cited by the reference notes this report draws on) documents the identical situation as "a real privacy gap": canvas content is plaintext on the wire and at rest even in groups where messages are end-to-end encrypted, it was undocumented, and the fix required a disclosed one-time popup, a `docs/PRIVACY.md` section, and a standing PR rule that "no PR that adds new canvas event kinds may merge without explicitly stating which side (plaintext or encrypted) it lives on."

`security.md` for this project pre-wires every user with an identity keypair specifically so opt-in E2EE DMs can ship later without a rewrite, and shapes the moderation model around that ("moderation APIs are deliberately metadata- and report-driven, not content-scanning" because encrypted content may not be server-readable).
`database.md`'s schema gives `messages.content` an `is_encrypted` escape hatch for exactly this reason but gives `canvas_objects.props` and `canvas_ops.patch` no equivalent provision.
The plan under review inherits none of this: it designs a permanent, unencrypted, replayable-by-seq audit log of everything anyone ever drew or pasted, with no disclosure mechanism, no encrypted-payload path, and no acknowledgment that the rest of the project is deliberately keeping the door open for E2E content.
If E2EE DMs or encrypted groups ship later, canvas either stays a silent, undisclosed exception (repeating echo's exact undocumented gap) or needs the schema, key-rotation, and re-encryption-of-history work `04-encrypted-canvas.md` describes as "non-trivial state to manage," none of which this plan anticipates.

### 3. No streaming/pan-load protocol for a canvas that can hold 20,000 objects across a 10,000,000px world

The plan specifies viewport-first pagination only for the late-join fetch ("late joiners fetch current materialized state, keyset-paginated by seq, viewport-first... under 500KB").
It never specifies how objects load as a client pans away from its join point.
A soft target of 20,000 objects on Linux spread across a ±5,000,000px world cannot be resident in the client's spatial grid all at once under the stated 500KB/60fps budgets, so the client either re-fetches on pan (a mechanism nowhere described: no subscription, no viewport-delta query, no cache-and-diff protocol) or the "viewport-first" load only ever covers the join moment and the rest of a large canvas is effectively unreachable by panning.
This is the single biggest functional gap in the plan: the object-count and world-size targets are set without the fetch protocol needed to make them true. Without this, "infinite," even the bounded version this plan defines, does not actually work past the first screenful.

## Major findings

### 4. The plan rejects a hard object cap that a sibling report assumes exists

`voice-canvas.md`'s growth-policy section explicitly rejects "a hard DB-enforced cap with silent rejection... as user-hostile" in favor of a soft, UI-surfaced warning only.
`security.md`'s abuse-and-rate-limiting section lists "canvas mutation and object caps" alongside connection caps and per-user message limits as an expected server-side abuse control.
As written, there is no enforced ceiling anywhere: a compromised client, a scripted API client bypassing the UI, or a bug that spams commits can grow a single channel's object count without bound, since the per-op rate limit (20/s/user, per `realtime-sync.md`) only slows growth, it does not cap it.
On a small self-hosted instance this is a real storage- and query-latency exhaustion vector against exactly the deployment profile (a handful of users, minimal admin tooling) the brief cares most about protecting.
The plan needs either a high, rarely-hit hard ceiling with a clear error (not silent rejection, echo's actual mistake) alongside the soft UI warning, or an explicit argument for why no technical ceiling is needed.

### 5. LiveKit integration for presence objects is assumed by the render architecture but never designed

The five-layer render plan includes "L4 presence video textures (camera bubbles, screen shares)" and culling that "extend[s] to media subscriptions," but `voice-canvas.md` never mentions LiveKit, SFU, track identity, or subscription lifecycle at all.
`media.md`, the sibling report that actually owns this integration, specifies that canvas objects for bubbles and screen shares must carry "a track reference" pointing at a stable LiveKit participant/track identity, and that off-viewport bubbles must be fully unsubscribed from LiveKit, not just culled from paint, or SFU cost scales with total participants instead of visible ones.
None of this appears in the canvas object model (`props JSONB` is never shown holding a track reference), the ephemeral presence broadcast channel, or the culling pass described in `voice-canvas.md`.
Left unresolved, this is exactly the kind of two-specialist gap that produces the "video pixels leak into the canvas data model" bug class `media.md` warns against, and it is a nontrivial implementation gap in a plan that otherwise claims the render architecture only needs "two new layers" added to a reused base.

### 6. Undo has no authorization model, in a plan whose own project treats canvas as "the sharp case" for server-side authorization

`security.md`'s verdict is explicit: "every collaborative mutation must be authorized and validated server-side, since trusting client-broadcast mutations is a classic real-time-collaboration vulnerability," and defines a dedicated `canvas-edit` permission flag.
`voice-canvas.md` never mentions permission checks anywhere, and its undo design ("undo emits a new inverse op") does not say who may invert whose op.
Concrete failure: a channel member holding only `canvas-edit` (not `moderate`) can emit an inverse patch targeting any object, including one authored and pinned by another member or an admin, silently reverting their work with no distinguishable audit signal beyond "another op happened."
This is a griefing vector the object model's own `from_user_id` field could trivially prevent (restrict undo to the object's author, or require `moderate` to invert someone else's op) but the plan does not say so.

### 7. Presence/content shared z-order is a real mechanism gap, not just added complexity

The plan resolves the presence-vs-content tension by giving presence objects "a slot in the same z-order... via a lightweight in-memory per-channel z-counter" while keeping their position updates on a pure ephemeral broadcast, explicitly reversing echo's own Phase-0 "whiteboard-first" decision to demote presence off the canvas entirely.
Reversing that decision is defensible given the brief's explicit "arrange everything in space" requirement, and the report says so.
What is not addressed: an in-memory z-counter resets on every server restart while `canvas_objects.z_index` is durable and can reach large historical values after months of use, so post-restart presence objects and long-lived content objects are drawing z-index values from two authorities with no defined relationship, and a reconnecting client has no persisted history to replay ephemeral z-order changes from, only whatever the current broadcast state happens to be. Two clients that reconnect at different moments during a z-order flurry can end up with permanently different presence-vs-content stacking until the next explicit reorder event, with no mechanism described to detect or correct the divergence.

### 8. Server idle-RSS budget openly contradicts a sibling report, and this plan is the one that needs to change its language

`performance.md` flags, without prompting from this review, that `voice-canvas.md`'s "150MB idle RSS for the whole process" is five times `backend.md`'s 30MB idle figure for the same process, and recommends relabeling the canvas number as a light-activity ceiling, not an idle baseline.
That the inconsistency needed a third report to catch and patch is itself a signal that this plan was not checked against the budgets already committed elsewhere in the same research pass before being written down as if settled. The fix is a one-line label change, but as written the number is simply wrong for what it claims to measure.

## Minor findings

### 9. Screen-share tiles assume native-resolution source frames that iOS may not actually have

`voice-canvas.md`'s coordinate section states "a shared screen's native-resolution content is aspect-fit into its tile's world-space box entirely at paint time," implying full-resolution source frames are always available to zoom into.
`media.md` notes iOS screen share goes through a ReplayKit broadcast extension capped at roughly 50MB of memory, "a real constraint on frame buffering to load-test early." A user zooming into a screen-share tile expecting native resolution may instead be looking at whatever reduced frame the extension's memory ceiling forced, and the plan does not acknowledge this interaction at all.

### 10. Overbuilt for the brief's own self-host target

The brief states "a self-hosted server with only a handful of active users should remain extremely lightweight."
The plan's mip-tier decoded-bitmap cache with thumbnail-always-resident/full-res-near-zoom swapping, an 8-GIF concurrency cap with static-frame fallback, and a 20,000-object soft-cap warning system are real, ongoing maintenance surface (the plan's own risk note admits "five render layers add coordination complexity") built for a scale a small self-hosted friend-group deployment is unlikely to ever approach. None of this is wrong to build eventually, but the plan presents it as day-one scope rather than flagging which pieces could reasonably follow object-count telemetry instead of being built pre-emptively.

### 11. GIF and mip-tier cache scope (per-client or per-channel) is unstated

"A hard cap of 8 concurrently-animating GIFs" does not say whether this is per-viewport, per-client, or per-channel. If per-channel and enforced globally, a channel with many pasted GIFs during an active session could have most of them silently frozen for every participant regardless of what each individual is looking at, which is a materially different UX than a per-viewport cap.

## Open questions the specialist should have raised but did not

- How does the canvas seq/ID scheme interoperate with the unified cross-conversation catch-up sync endpoint the rest of the system is designed around (see finding 1)?
- What is the disclosed privacy posture for canvas content, now and after any future E2EE DM work (see finding 2)?
- What is the actual client-server protocol for loading objects as a user pans far from their join point (see finding 3)?
- Who is authorized to undo whose op, and how does that interact with the permission model (see finding 6)?
- What happens to presence z-order state across a server restart or a client that reconnects mid-reorder (see finding 7)?
