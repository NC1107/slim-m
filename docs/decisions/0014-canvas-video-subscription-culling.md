# 0014 - Viewport-driven video subscription culling on the canvas

Date: 2026-08-11
Status: accepted, implemented

## The clause this closes

`docs/ROADMAP.md`'s Phase 5 has three exit-criteria clauses.
Two were met with measured numbers in 2026-07 by the two canvas spikes; the third, "flicker-free media culling on Fedora and iOS", had no implementation and, until PR #557 settled it on 2026-08-11, no agreed reading either.

The settled reading, restated here so this record stands on its own: `docs/STRATEGY.md` names the mechanism as "ties LiveKit adaptiveStream and dynacast to canvas zoom and fully unsubscribes tracks outside the viewport, with a hysteresis margin and debounce so panning near the boundary does not flicker or thrash keyframes."
`docs/research/canvas-spike-client.md` names the same thing in its own list of what it did not cover: "LiveKit subscribe and unsubscribe hysteresis near the viewport boundary."
That is distinct from the in-memory uniform-grid *object* culling the same phase's first deliverable already validates, and the two must not be conflated.

## What was already there, checked rather than assumed

PR #557's own confirmation - "`CanvasPresenceLayer` renders every call participant's tile unconditionally" - is not what the code does, and finding that out changed the design.

`CanvasPresenceVisibility` (`client/packages/voice_canvas/lib/src/canvas_presence_visibility.dart`, shipped 2026-08 with the camera-bubble work in PR #413) is already a real, mutation-tested, two-threshold spatial hysteresis band: an unmounted tile mounts once it enters a 200-world-unit margin around the viewport, and a mounted one stays mounted until it leaves a 600-unit one.
Both `CanvasPresenceLayer` and `CanvasPresenceBackdrop` run it, and a tile outside the exit band renders no widget at all.

That band already reaches further than it looks.
`adaptiveStream: true` is set at room construction, so `RemoteTrackPublication` polls its own view registrations every 300ms; a tile with no mounted renderer has none, which resolves to `disabled: true` and, after a 1500ms debounce, an `UpdateTrackSettings` telling the SFU to stop forwarding that track.
So the *bandwidth* half of the roadmap clause has in practice been met since PR #413, by a mechanism nobody wrote down as meeting it.

What none of that releases is the subscription: the transceiver and the decoder stay allocated for the whole call.
On a device with a bounded number of hardware decode sessions - the roadmap names iOS explicitly - that is the cost that actually bites on a canvas carrying more tiles than fit on screen.
Nothing in the client had ever called `RemoteTrackPublication.unsubscribe()`, which does exist on the locked `livekit_client` 2.10.0 and does what it says.

## Decision

Add a second, slower stage behind the spatial band that already exists, rather than a parallel mechanism beside it.

The canvas declares, through one new seam, which presence tiles currently want video.
The `rtc` package unsubscribes any remote video publication that has been outside that set for a dwell, and resubscribes immediately when it comes back.

### The seam

`VoiceSession.setVideoInterest(Set<String>? tileKeys)`, taking the canvas's own `'<kind>:<identity>'` tile keys.
No LiveKit type crosses the package boundary, which is the constraint `VoiceSession.screenShareViewFor` already exists to honour.

The set is reported by `CanvasPresenceLayer` and is *exactly* the set that widget just used to build its own children, never a second computation beside it.
That matters: a separate "what is on screen" calculation would be a second authority over one fact, which this project's own canvas module doc already names as its worst residual class of bug.
`CanvasPresenceBackdrop` needs no report of its own, because it runs the identical visibility band over the identical rects and then narrows to the sent-to-back subset, so the union of tiles carrying real video across both widgets is precisely the layer's own visible set.

**Null is not an empty set.**
Null means "this caller has no opinion, subscribe everything"; empty means "nothing on this canvas wants video", which is a real and correct answer for a fully hidden or fully off-screen roster.
Conflating them is what would let a canvas open on channel A silently tear down a call running on channel B.
This is the same null-versus-zero split `SyncController`'s `opCursor` already draws, and for the same reason: there is no in-band value that could carry the first.

### Hysteresis, concretely

Two layers, and only the second is new.

**Spatial: 200 world units to enter, 600 to leave.** Unchanged, `CanvasPresenceVisibility`'s own existing numbers, already justified in that file's doc and already mutation-tested. A tile must cross 600 units past the viewport edge before it is even a candidate for a cull.

**Temporal: a 3-second dwell before unsubscribing, and no dwell at all before resubscribing.**
Three seconds is chosen against two real numbers rather than picked.
It is twice `RemoteTrackPublication`'s own 1500ms `UpdateTrackSettings` debounce, read out of the locked package source, so LiveKit's cheap pause is always already in flight before the expensive teardown fires - the layering is the point, a full unsubscribe only ever reaches a track the cheap answer has already been applied to and still not been enough for.
And it comfortably outlasts a pan out and back, which the 600-unit band has already made rare on its own, so the ordinary "look over there, look back" gesture never reaches this timer at all.

The asymmetry is deliberate: the cost of being slow to resubscribe is a black tile somebody is looking at, and the cost of being slow to unsubscribe is a little memory nobody can see.

### Audio is never culled

Not as a check bolted on, but as two independent guarantees that fail separately.
`VoiceSession`'s room walk reads `videoTrackPublications` only, so an audio publication is never offered to the culler at all; and the culler refuses to act on any key whose kind is not `camera` or `screen`, whatever reaches it.
The second is what a test can drive, and does.

### Screen share is culled, and that is safe here specifically

A screen share is the highest-bandwidth thing in a call, so culling an off-screen one is the biggest single win, but it is only safe because of a fact worth writing down rather than assuming: while the canvas pane is open, `CanvasPresenceLayer` and `CanvasPresenceBackdrop` are the *only* surfaces in this client rendering a remote camera or screen share.
`home_shell.dart`'s stage ternary makes `CanvasPane` and `VoiceScreen` mutually exclusive branches, and the fullscreen video overlay is reachable only from `CallStageLayout`, which lives inside `VoiceScreen`.
So no other live surface can be showing a track the canvas has decided it does not want.

**That fact is load-bearing and it is not enforced by anything.**
A future change that renders a camera or screen share alongside an open canvas - a picture-in-picture strip, a second pane - has to widen the interest set to the union across surfaces before it ships, or it will tear down video somebody is watching.

### The tile-key convention is one shared function

`videoSubscriptionKey({identity, screenShare})` in `rtc` is now the only place a `'<kind>:<identity>'` key is built, and the canvas's `presenceTileKeys` calls it.
Two matching string literals in two packages would have drifted eventually, and this particular drift does not degrade gracefully: an interest set naming keys no publication can match culls every remote video in the call after three seconds.

## Alternatives considered

**Do nothing, and record the clause as met by `adaptiveStream`.**
Defensible on bandwidth, which really is already handled, and this was seriously considered.
Rejected because the roadmap clause says "fully unsubscribes" in as many words, and the resource half it is pointing at - decoder sessions, transceivers - is real and is exactly the thing that would bite first on the platform the clause names.

**Drive the cull from LiveKit's own view-registration signal instead of an explicit seam.**
Attractive, because that signal already aggregates across every surface in the app and so could never tear down a track something is showing.
It cannot work: unsubscribing sets the publication's track to null, so no renderer can mount, so the very signal that would ask for it back is destroyed by the act of culling. Resubscribing needs a declaration that survives the track being gone.

**Unsubscribe with no dwell.**
Rejected on the resubscribe cost: a renegotiation round trip plus a keyframe wait, visible as a black tile, for a saving that is invisible.

**Cull on zoom explicitly, as `docs/STRATEGY.md`'s wording suggests.**
Not built as a separate mechanism, because `adaptiveStream` already does the zoom half properly and automatically: tile rects are converted to screen space through `presenceScreenRect`, which multiplies by `camera.zoom`, so a zoomed-out tile really is laid out small and LiveKit requests a correspondingly small simulcast layer from its own measurement of the renderer. A second, hand-rolled zoom threshold would be a worse copy of a thing that already works.

## What is not verified

None of this has been confirmed against real cameras on real hardware, and it cannot be from here.
The state machine is mutation-tested, the canvas's reporting is driven through the real widget tree, and the LiveKit behaviour it composes with (`adaptiveStream`'s 300ms poll, the 1500ms debounce, `unsubscribe()`'s own semantics) is read from the locked package source rather than observed.
Whether a real SFU resubscribes fast enough for the resubscribe to look instant to a person, and whether the decoder saving is measurable on an iPhone, are both open, and are the owner's to check.
This is the same evidentiary bar every other untested-on-device media surface in this client already carries.

~~Also unverified, and worth naming separately: the `VoiceSession` glue itself - the room walk mapping `TrackSource.camera`/`screenShareVideo` to the two tile kinds, and the call into it from `_refreshParticipants` - has no unit test, because building a `lk.Room` carrying real remote publications needs a signalling server. The pure parts either side of it are tested; that seam is read, not driven.~~
Narrowed 2026-08-11: the mapping itself is unit-tested now, without a `lk.Room`.
`voice_session_video.dart`'s walk was split at the one place it needed to be - `RemoteVideoPublicationRef` (`rtc/lib/src/remote_video_publication.dart`) describes a publication as a plain record carrying `lk.TrackSource` (a bare enum, not a live object) rather than an `lk.RemoteTrackPublication`, and `mapVideoSubscriptionRefs` is what decides `TrackSource.camera`/`screenShareVideo` become which tile key, that the two are never confused for the same participant, that a participant with both yields both, and that an unrecognised source is skipped rather than guessed at.
`remote_video_publication_test.dart` drives all four directly, with a fixture built so the confusion it rules out is one the mapping could actually make (one participant, two publications, distinct recorded closures per key) rather than one no fixture with a single publication could ever expose.
What still cannot be driven, and could not be without standing up a real signalling server the way `livekit_client`'s own `remote_track_publication_test.dart` does (a mock peer connection and a captured websocket, just to construct one `RemoteTrackPublication`): the room walk itself, `_remoteVideoPublications`, which turns a real `lk.Room`'s `remoteParticipants`/`videoTrackPublications` into those plain records.
That walk is three lines with nothing left in it to decide - it is a real `lk.Room`, not a decision, that the test still cannot reach.
