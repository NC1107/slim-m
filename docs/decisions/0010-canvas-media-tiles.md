# 0010 - Canvas media tiles: camera and screen share as movable AR objects

Date: 2026-08-06.
Status: accepted.

## The owner's own words, verbatim

> On canvas my camera or screenshare should appear as an item on the canvas
> that can be moved and resized but it's stuck to the dock meaning you can't
> interact with it with draw tools and such

> Imagine like you are watching your friend play a game in the voice call and
> you move his camera over the top left of his gameplay and put a note down to
> record clues for the game he's playing kinda vibe, the goal is just to have
> control over the canvas like it's AR environment in a way make the screen as
> big or small as you want, draw on it, hide it, lock it in place kinda thing

This is the Voice Canvas's stated reason to exist (`docs/BRIEF.md`: "floating
camera bubbles for participants," "floating screen shares," "moveable
windows," "resizable windows" - "think of it as if users were wearing AR
glasses"). Camera bubbles and screen-share tiles were named in the Phase 5/6
notes as deliverables with no spike evidence behind them; this is that slice,
specified by the person who asked for it.

## What this reverses

A few hours before this work, the self camera bubble became a
screen-anchored corner tile (drag clamped to screen space, snapping to one of
four corners), and a follow-up merged remote bubbles into a screen-anchored
face-pile for the same phone-width crowding reason. That work sat on branch
`design/remote-presence-off-world`, held unmerged specifically because it
goes the opposite direction from what the owner asked for.

Read literally, "stuck to the dock" is the direct complaint about that
screen-anchored shape: a tile pinned to one corner of the *screen* blocks
whatever part of the *world* happens to pan under that corner, permanently,
rather than sitting at one place a person chose. World-anchoring closes that
structurally - the blocked region moves through the world with the tile
itself, which the user controls, rather than being a fixed screen-corner
hole in what is drawable.

## The five questions, decided

### Is a media tile a canvas object, or a different thing that behaves like one?

**A different thing.** `docs/STRATEGY.md`'s own Voice Canvas section already
settled this before any of this slice was built: "camera bubbles and
screen-share tiles are ephemeral presence objects never written to the op
log and reset on rejoin." This slice extends that existing line - never
reopens it - to cover position, size, lock and hidden state as well as the
bubble's mere existence.

Making a tile a real `canvas_objects` row would mean: a server migration, a
new object kind, op-stream entries for state that means nothing once the call
ends, and duplicating hit-testing, selection, resize and z-order machinery
the real object kinds already have. All of that cost buys nothing a call
does not already give for free - a tile's presence is derived from
`VoiceParticipant`, which the client already has.

### Is the arrangement shared or personal?

**Personal, one viewer at a time.** The owner's own example is a personal
act: arranging a friend's camera over their gameplay to take his own notes,
for his own reference. Nothing in the request asks for a second viewer to
see the same layout.

This also extends an existing precedent rather than inventing one: the self
bubble's resting corner was already a local, per-device preference
(`canvasSelfBubbleCornerKey` in `SharedPreferences`), never sent to anyone.
This slice generalises that shape to free-form position, size, lock and hide,
for every tile, not just the caller's own.

The cost, stated rather than hidden: two people on the same call can see
their friend's camera in two different places. That is judged the right
trade rather than a gap, for two reasons. First, it is exactly what the
owner's own example describes - an AR overlay is inherently a personal view
of a shared scene, the same way two people wearing AR glasses looking at the
same room would each be free to pin a virtual note wherever suits them,
without demanding the other party see it in the same spot. Second, going
shared would mean putting position, size and lock on the wire and giving it
some sync story (ephemeral relay frames per drag, most likely) for a feature
whose entire value is achievable without it, and this project's own
knowledge base already documents exactly this class of cost/benefit call for
polls, reactions and pins (`0009-reactions-pins-polls-reconciliation.md`) -
build the cheap answer until real evidence says otherwise.

### Lock: what does it mean, and does it bind for everyone?

**Local, per-tile, per-viewer. Locked means the tile stops intercepting the
pointer at all**, not merely "can't be dragged." An unlocked tile behaves
like every other movable thing on this canvas: it wins the pointer within
its own bounds, which is why it can be dragged and resized, and which is
also why a drawing tool cannot draw through it - the same trade every other
movable canvas object already makes. Locking flips that: the tile's content
becomes `IgnorePointer`, so a pan, a stroke, or an erase gesture reaches
straight through it to the canvas underneath, exactly answering "you can't
interact with it with draw tools." The lock control itself is never wrapped
in that `IgnorePointer` - a locked tile is never a dead end, since the one
thing still reachable is the button that unlocks it.

Locking does not bind for the other party, for the same reason position
does not: it is a property of a personal arrangement, not a fact about the
call.

### Hide: does it mean the same thing it already means for the self bubble?

**Two related but distinct things, kept apart on purpose.** The self
bubble's existing "Hide my camera bubble" toggle
(`canvasSelfPresenceProvider`) is untouched: a standing, persisted,
device-wide "I never want to see my own camera on any canvas" preference,
independent of any one call.

Every tile - self, remote, camera or screen share - additionally gets its
own on-tile hide control, backed by `CanvasPresenceTileOverrides`, which is
per-call and resets on rejoin (`prune`), matching the "reset on rejoin" shape
the rest of a tile's state already has. This is what closes the case the
owner's own example implies without saying: decluttering a busy call by
hiding one participant's tile for the rest of that session, without
committing to never seeing them again.

A hide must stay reversible, or it is a delete wearing a softer name.
`CanvasOverflowMenu` gains a "hidden tiles" section listing every tile hidden
this call, each with its own "Show" action, alongside the self bubble's own
existing toggle.

### Draw on it: does ink drawn near a tile stay with the tile if it moves?

**No, deliberately, and this is the one place the owner's own framing is not
literally satisfiable without inventing a new structural feature.** Ink is a
real, shared canvas object, anchored to a world position. A tile's position
is now personal and per-viewer. Those two facts together mean "attach this
note to that tile" has no single answer once two viewers can have the tile
in two different places - there is no one world position the note could be
anchored to that both viewers would see it sitting on the tile.

No canvas object kind supports parenting or attachment today (this was
checked, not assumed - `canvas_document.dart`, `canvas_hit_test.dart`, and
`canvas_ops_controller.dart` all treat every object as independent, and this
project's own change log records several passes over this exact code with
no such concept ever proposed). Building one now - object groups, relative
coordinates, a parent-child z-order rule, and a decision about what happens
to attached ink when the parent tile is hidden or resized - is a real,
separate structural feature, not a corollary of media tiles, and it would
need its own spike the way the canvas's spatial index did.

The practical mitigation, which is what the owner's own example needs and
already works today: draw the note in the world region where the tile
currently sits. As long as the tile is not moved again, the note reads as
attached to it, because it visually is - the same "not attached, but
practically fine because nobody moves things constantly" property this
canvas's ordinary content already has. If the tile *is* moved later, the note
stays where it was drawn, which is a real, named limitation rather than a
silent one.

### Camera versus screen share: one feature or two?

**One shared manipulation contract, two distinct tile kinds** - the same
"window is a behaviour, not an object kind" precedent
`0004-visual-identity-review.md` already settled for real canvas objects,
extended here to presence. A screen share is visually and functionally
different enough to earn its own default size (360x203, a 16:9-ish shape,
against a camera tile's 220x160 on / 140x140 off) and its own glyph and
label, but drag, resize, lock and hide are exactly the same code path for
both - `CanvasPresenceManipulableTile` does not know or care which kind of
content it wraps.

## What got built

- `CanvasPresenceTileOverrides` (`client/packages/voice_canvas/lib/src/canvas_presence_tile_overrides.dart`):
  the pure, off-Riverpod, per-tile state store - rect, locked, hidden, and a
  touch-order z-index - keyed by an opaque `'camera:<identity>'` /
  `'screen:<identity>'` string, with `prune` closing the "reset on rejoin"
  loop.
- `CanvasPresenceLayer` (`client/packages/app/lib/src/screens/canvas/canvas_presence_layer.dart`,
  rewritten): renders self and remote, camera and screen share, all through
  one world-anchored list. `CanvasSelfPresenceOverlay`, the screen-anchored
  self-only layer, is deleted outright rather than kept alongside.
- `CanvasPresenceManipulableTile` (`client/packages/app/lib/src/screens/canvas/canvas_presence_tile.dart`,
  new): the drag/resize/lock/hide interaction, self-contained rather than
  routed through the tool-based gesture state machine real canvas objects
  use, since a tile's manipulation has never depended on which tool is
  currently armed.
- A z-order fix found only by rendering the result: the first version painted
  tiles in roster order regardless of which one a viewer had just dragged in
  front, so an untouched participant's default-positioned tile could sit
  over one this viewer had deliberately brought forward. `zFor`/the touch
  order in `CanvasPresenceTileOverrides` is the fix, and
  `canvas_presence_layer_test.dart` carries the regression test.
- `canvasSelfPresenceProvider` drops its `corner` field entirely; `hidden`
  is unchanged.

## What was left, and why

- **Ink attached to a tile.** Explained above - a real structural feature,
  not built here.
- **A keyboard or screen-reader route to drag, resize, lock or hide a
  tile.** Pointer-only, matching every other drag or resize interaction this
  canvas already has (a real canvas object's own resize handle is pointer-only
  too). Not a new gap this slice introduces, but not closed either.
- **The presence roster (the small "who's here" face-pile,
  `canvas_presence_roster.dart`) can still visually sit over a tile that
  happens to pan into its fixed screen corner.** Confirmed by rendering a
  phone-width scene with several participants: the roster paints on top of
  everything in the surface Stack, including a tile's own lock/hide
  controls, when both land in the same screen region. This is not new -
  the pre-existing code already special-cased exactly one corner collision
  (the self bubble's own resting corner) precisely because this tension
  already existed - but a tile is now free to pan anywhere, so the one
  special case that used to paper over it no longer can, and no general
  collision-avoidance was built to replace it. Recorded rather than solved,
  the same "state plainly rather than solve" call the note-attachment
  question above already makes for a harder version of the same shape.
- **Default arrangement collision avoidance against existing ink.** A fresh
  tile's default position still comes from `CanvasPresenceLayout`, which
  places tiles in a row starting near the world origin with no awareness of
  what has already been drawn there. This was already true before this
  slice (remote bubbles already arranged this way); the mitigation is the
  same as before, now stronger: a tile can be dragged away, resized down, or
  locked so drawing tools reach through it, where previously a remote bubble
  could only be dragged nowhere at all.
