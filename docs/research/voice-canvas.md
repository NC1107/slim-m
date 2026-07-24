# Infinite Voice Canvas: Design Report

Source material: the echo-messenger reference notes (`decentralized-chat-app/reference-echo-messenger.md`) and its own `docs/voice-lounge/*` decision-of-record folder.
This report designs a fresh implementation for slim-m, reusing what worked in echo-messenger and deliberately not repeating its two biggest mistakes: the flat-JSON-array data model and the ordering-free sync layer.

## A note on "infinite"

The brief asks for a literally infinite canvas.
No shipping product actually does this: Figma and Miro use a very large but bounded coordinate space, plus a client-side recentering trick so float precision does not degrade far from the origin.
I am adopting the same approach and flagging the brief's wording as slightly imprecise rather than silently building something unbounded.
The world coordinate space is double-precision, with a soft practical bound of plus or minus 5,000,000 logical pixels, large enough that no real user hits the edge and small enough to keep spatial indexing and float math well-behaved.
This avoids echo-messenger's actual mistake, which was not "bounded" but "arbitrarily resized three times because nobody decided the policy up front."

## Object model

Echo-messenger's worst structural decision was two flat, append-only JSONB arrays per channel with a hard 2000-item cap.
It could not support z-order, transforms, grouping, or undo, and every image update rewrote the entire array.
slim-m starts with a real per-object table from day one:

```
canvas_objects(
  id, channel_id, kind,          -- 'stroke' | 'image' | 'gif' | 'window'
  z_index, transform (x,y,w,h,rotation),
  props JSONB,                   -- kind-specific payload
  from_user_id, seq, created_at, updated_at, deleted_at
)
```

Two object families exist.
Content objects (stroke, image, gif, window) are persisted, versioned, and undoable.
Presence objects (camera bubble, screen-share tile) are ephemeral, never written to this table.
The brief's "AR glasses, arrange anything in space" metaphor wants camera bubbles and screen shares to live in the same coordinate space and z-order as drawings, which is correct and worth keeping.
Echo-messenger's own later audit recommended the opposite: demote avatars out of canvas coordinates entirely into a roster overlay, because presence and content have different persistence and update-rate needs.
Both are right about different things.
The resolution here is to share the coordinate space and z-order, but not the persistence path: presence objects get a slot in the same z-order (so a sticky note can sit on top of a camera bubble) via a lightweight in-memory per-channel z-counter, while their position updates go over a pure ephemeral broadcast channel that never touches the op log.
This closes the "product-identity conflation" gap without losing the AR-glasses UX the brief explicitly asked for.

"Moveable, resizable windows" is not a fifth object kind.
It is the shared interaction contract (drag, resize handles, bring-to-front) applied to image, gif, camera_bubble, and screen_share_tile.
Strokes do not get that contract in v1: they are drawn, not repositioned, which keeps the gesture surface simple.

## Sync and conflict model: verdict

Server-authoritative op log with a per-channel monotonic `seq`, not a CRDT.
Every persisted mutation (create, move, resize, delete) is assigned the next `seq` inside the same transaction that writes `canvas_objects`, exactly the fix echo-messenger's own architecture assessment recommended and never shipped.
Clients apply ops in `seq` order, not WebSocket receive order, which by itself eliminates every concrete divergence bug the reference notes documented: clear-resurrection, image-move races, and late-joiner double-apply all stem from ordering by arrival time instead of a server-assigned total order.
A `clear` op gets a seq like any other; anything with a lower seq is included in its scope, anything higher is not, so a stroke that was mid-flight when a clear was issued cannot resurrect itself out of order.

CRDTs were seriously considered and rejected.
Their value is offline-first multi-writer merge across disconnected replicas, which this feature does not need: the Voice Canvas only exists during an active voice call, which already requires a live WebSocket to one authoritative server, unlike a Figma-style always-open document that gets edited offline for days.
A CRDT would add tombstone garbage collection, a larger client dependency, and a genuinely harder mental model for moderation: a delayed remote CRDT delete-then-reappear is structurally the same clear-resurrection bug, just relocated into the merge algorithm instead of fixed.
The op log's real cost is that it requires the server to be reachable to make any edit, which is already true of every other mutation in the app, so this is not a new constraint.

Conflicting concurrent edits to the same object (two users dragging the same image) are resolved last-write-wins by seq, with an advisory-only "user X is moving this" broadcast hint so other clients avoid grabbing the same handle mid-drag.
That hint is not server-enforced locking; enforcing it would reintroduce per-object lock state on the server for a UX nicety that a live call already makes rare in practice.

## Persistence and history

The materialized `canvas_objects` table is fed by an append-only `canvas_ops` log (`channel_id, seq, actor_user_id, op_type, object_id, patch, created_at`).
This gives history and undo almost for free: undo is not a special history rewrite, it is a normal new op that emits the inverse patch and gets its own seq.
Late joiners fetch current materialized state, keyset-paginated by `seq`, viewport-first, not the reference's unpaginated whole-board response.
The op log doubles as the moderation audit trail the brief asks for ("who drew what, when").
Raw op payloads older than roughly 30 days can be compacted or archived once no client needs to replay from an arbitrary historical point; this is a v1.x job, not a launch blocker, given the self-host "handful of users" scale target.
In-flight drag frames are relay-only with a `commit: true/false` flag, reusing echo-messenger's proven fix for write-amplification during drags; only the pointer-up frame persists.

## Coordinate space discipline

Every object type uses absolute world-space double-precision coordinates, with no exceptions.
Echo-messenger's screen-share bug happened because one entity type used device-local CSS pixels while everything else used shared canvas-world space.
The fix here is structural, not a migration shim: a shared screen's native-resolution content is aspect-fit into its tile's world-space box entirely at paint time, so no viewport-relative coordinate is ever serialized onto the wire.

## Flutter rendering architecture

Keep, unmodified: the explicit pointer-count gesture state machine (idle, drawing, panning, pinching) driving a single root `Listener`, and the three-layer `RepaintBoundary` split with the in-flight stroke living in a plain `ChangeNotifier` outside Riverpod.
Both are correctly identified in the reference notes as good enough not to touch.

New for a large, zoomable world: a uniform grid spatial index (2048px cells, not an R-tree, favoring simplicity) over the current channel's materialized objects, queried each frame against the expanded viewport rect to produce a culled candidate list before any exact AABB test runs.
A recenter-on-drift technique rebases the render matrix to a local origin whenever the camera drifts more than 100,000px from the last rebase point, avoiding float precision artifacts far from the world origin, the same technique Figma and tldraw use.
Rendering splits into five layers: L0 background grid (unchanged, already judged "Figma-grade"), L1 committed strokes (Expando-memoized outlines, identity-based `shouldRepaint`, unchanged), L2 in-flight local stroke (unchanged), L3 images/gifs/windows with a bounded LRU decoded-bitmap cache and a mip-tier swap (thumbnail always resident, full-res only near current zoom), and L4 presence video textures (camera bubbles, screen shares) as their own boundary so LiveKit's 30 to 60fps video updates never trigger stroke or image repaints.
Offscreen GIFs pause animation using the same culling pass; concurrently-animating GIFs are capped at 8, others show a static first frame, bounding CPU on both platforms.

## Performance budgets

Server: idle RSS under 150MB for the whole process; per-channel presence state under 1MB; canvas-state query p99 under 5ms at 20,000 objects on a 1 vCPU/1GB Postgres instance; steady-state WS traffic per actively-drawing user under 20KB/s.

Client: 60fps steady-state pan/zoom on Linux and iOS up to 5,000 loaded objects per channel on a mid-range iPhone and 20,000 on Linux desktop; active-stroke repaint under 2ms per pointer sample; decoded-bitmap cache capped at 96MB on iOS and 256MB on Linux; initial late-join fetch under 500KB via viewport-first pagination.
Beyond the object-count targets, growth is a surfaced soft policy cap ("this canvas is getting large"), never a silent technical wall like the reference's 2000-item drop.

## Open questions

Retention policy for canvas op-log history (how long to keep raw, replayable history versus audit-only) is a product decision, not a technical one, and is left open.
Whether screen-share and camera-bubble presence objects should optionally persist their last position across a full server restart (today: reset on rejoin, matching echo-messenger's proven pattern) is worth revisiting once real usage data exists.
