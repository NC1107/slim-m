# The end-to-end harness

`scripts/e2e.sh` stands a whole deployment up, drives two clients through the
product, and tears it down.
Nothing in it is mocked: a real LiveKit SFU, the release server binary, the real
web build, and two isolated headless browsers that talk to each other.

```bash
bash scripts/e2e.sh            # the whole run, then teardown
bash scripts/e2e.sh --keep     # leave the stack up afterwards to poke at
E2E_ONLY="reaction" bash scripts/e2e.sh   # one scenario, by name
E2E_REBUILD=1 bash scripts/e2e.sh   # rebuild the web bundle first
```

It needs docker, flutter, cargo, python3 with `websocket-client`, and a system
Chrome.
Screenshots land in `/tmp/e2e/shots`, one per interesting moment, and are
worth looking at after a failure: the harness writes one at the point it gives
up as well, with the browser's console log beside it under the same name.

Two of the files the web build needs at runtime are gitignored binaries, so the
script fetches them itself (`client/packages/app/tool/fetch_web_assets.sh`, a
no-op once they are present) and then checks the running static server actually
answers for each of them.
That check is worth its lines: without `sqlite3.wasm` the app signs in, loads
the member pane, and renders nothing but "Could not load channels." with sync
stuck offline, which reaches the harness only as a channel row that never
appears. See "Reading a red run" below.

It also runs in CI now, as `.github/workflows/e2e.yml`: on every push to `main`, on a nightly schedule, and by hand through `workflow_dispatch`.
It is advisory rather than required while it proves itself out; see `docs/ci.md` for the trigger reasoning and the promotion path.
Before that workflow existed this script ran nowhere and its failures went unnoticed for a real stretch of time, which is the reason it exists.

## What it checks, and against what

Every scenario drives the UI the way a person would and then asks the **server**
whether it happened.
That second half is the point.
A reaction chip that renders, a roster that fills, an avatar that appears: none
of those are evidence that anything was stored, and a client that only ever
agrees with itself would pass a run in which nothing was persisted at all.
The voice scenarios go further and ask the SFU directly, because a participant
tile is not a published track.

| Scenario | Driven through | Checked against |
| --- | --- | --- |
| sign-in, fingerprint, invite gate | the UI | the server's own session |
| a message each way | the UI | `GET /channels/{id}/messages` |
| a mention | the UI | the stored message text, verbatim |
| a reaction | the UI, through the picker | the message's `reactions` |
| an attachment | the UI, through the file picker | the message's `attachments` |
| a profile picture | the UI | `GET /users/{id}/avatar`, byte length |
| theme and status | the UI | the control's own reported state |
| personal vs Space settings | the UI | that neither shows the other's rows |
| who can join | the UI | `/space/settings` and `/version` |
| creating a role | the UI | `GET /roles` |
| a reply, and a reply to a deleted message | the UI (the send and the delete go over the API; see below) | `reply_to_id` stored, the quote naming its parent live, and the honest jump-failure notice once it is gone |
| a thread stays off the ordinary channel list | opening it is the API (see below), reading and replying is the UI | the channel list excludes it, and the parent message's own reply-count affordance |
| reporting, blocking | the API (see below) | the moderation queue, the block list |
| the capability handshake | the API | that `/version` names the two routes the run just used |
| permissions | the API | that a member is refused and an admin is not |
| a voice call, mute, leaving | the UI | the SFU's participant and track list |
| sharing a screen | the UI | a `SCREEN_SHARE` track on the SFU |
| the canvas dock keeps a call's own controls reachable | the UI | mute and unmute, clicked from inside the canvas's own dock, both reach the SFU |
| calling in a DM | the UI | the SFU's participant and track list, keyed by the DM's own channel id |
| edit, delete, search, pins, polls, invites, DMs, channel admin, devices, read state, sync | the API | the effect of each, not its status code |
| the Voice Canvas: draw, paste an image, place a note and a shape, move, resize, reorder, erase, clear, undo, reload | the UI (`e2e_canvas.py`, `e2e_canvas_shapes.py`; see below) | `GET /channels/{id}/canvas/objects`, `z_index` for the reorder, and the second client's own `performance` resource log for the pasted image's bytes |
| placing a shape selects it and arms Move, with no manual tool switch | the UI | a drag right after placing moves the object rather than adding a second one |

The run ends by reporting how many documented API paths it actually touched,
counted from what the harness and both browsers requested rather than from a
list kept by hand, since a hand-kept list overstates coverage the moment a
scenario changes. A full run currently reaches **42 of 70** documented paths
(confirmed against a live run rather than assumed; the schema has grown
since this number was first written, the harness's own reach has grown with it).

What it does not reach divides into two: routes that need a second
deployment or real hardware (push, the relay lifecycle, account recovery),
and routes that are simply not covered yet (per-channel overwrites, assigning
a role to a member, kicking someone from a call, revoking one device, custom
emoji, redeeming a second invite, space analytics). The Voice Canvas closed
the third category this file used to name here; see "Driving a canvas app"
below for what that took. The remaining group is the honest backlog; the run
prints it every time so it cannot quietly grow.

## Layout

| File | What it owns |
| --- | --- |
| `scripts/e2e.sh` | the stack: SFU, server, web build, two browsers, teardown |
| `lib/e2e_run.py` | the running order, and the coverage report at the end |
| `lib/e2e_client.py` | one browser, over the Chrome DevTools Protocol |
| `lib/e2e_js.py` | the browser-side half: reading and driving the semantics tree |
| `lib/e2e_labels.py` | every accessible name the app is driven by, in one place |
| `lib/e2e_api.py` | the server's own answer, for checking against |
| `lib/e2e_messaging.py`, `e2e_settings.py`, `e2e_admin.py`, `e2e_voice.py`, `e2e_markdown.py`, `e2e_reconcile.py`, `e2e_replies.py`, `e2e_threads.py`, `e2e_dm_call.py`, `e2e_canvas.py`, `e2e_canvas_shapes.py` | the scenarios |
| `lib/e2e_sweep.py` | the API-level routes the scenarios do not reach |
| `lib/e2e_seed.py`, `e2e_fixtures.py` | the accounts and the two PNGs a run uploads |

Labels live in one module because they are a contract with the UI rather than
incidental strings: when one changes, exactly one line changes with it.

## Driving a canvas app

Flutter paints to a canvas and exposes nothing to a script until its
accessibility tree is on; one click on the placeholder it leaves in the DOM
turns every widget into an `<flt-semantics>` element with a real bounding box.
That is what makes this label-driven rather than pixel-driven, so a layout
change does not break it.

Four things cost real time to learn, and each fails silently rather than loudly:

- **Only the focused text field has an `<input>`.** Every other field on screen
  is paint, so a field is clicked once to bring its element into being, then
  focused by `aria-label` rather than clicked at coordinates.
- **The same label is painted onto a plain node and a tappable one**, and only
  the one carrying `flt-tappable` answers a click. The closest name wins, too:
  a channel row and its "Manage <name>" button both match the channel's name,
  and taking the last match opened the manage sheet every time. Two tappable
  matches with neither an exact name is resolved by nesting, not just length:
  a reply's quote button renders its own accessible label as inline text
  rather than an `aria-label` attribute, so its derived name is that text
  glued to its rendered snippet, which came out longer than the message row
  enclosing it - "shorter wins" then picked the row over the button it
  contained. A tappable node nested inside another tappable match is always
  the more specific one, so containment is checked before length.
- **The file picker's `<input>` never enters the document.** Flutter builds it,
  clicks it, and drops it, so there is nothing for `DOM.setFileInputFiles` to
  find; `createElement` is wrapped to catch it, and it is handed a real `File`
  through a `DataTransfer`.
- **Pointer events do not reach the canvas while the tree is on**, because the
  semantics elements sit over it. `gestures(True)` lifts them for the one
  affordance that has no label - the react button, which only exists while the
  pointer is over a message.

### Driving the Voice Canvas specifically

The signature feature is a `CustomPainter`, so it publishes almost nothing
else to the tree beyond what the general rules above already cover. Two more
things `e2e_canvas.py` and `e2e_canvas_shapes.py` (note, shape, reorder -
split out to stay under the file budget) lean on, documented at length in
`e2e_canvas.py`'s own module doc:

- **The one container `Semantics` node whose label starts "Canvas,"** states
  the live object count ("Canvas, 2 objects: 1 stroke, 1 image") and updates
  on every local and live change, so it is the main proof both clients agree
  without ever opening anything else. Its own bounding rect is also the
  coordinate frame every drawing and dragging gesture is placed in, since the
  camera starts at world `(0, 0)` with `zoom: 1` and this scenario never pans
  or zooms - a page coordinate and a world coordinate differ by exactly one
  constant offset for the whole scenario. A note or a shape is placed at a
  *fraction* of that rect's own live width and height rather than a fixed
  offset, because both run after the pasted image has already been dragged
  and resized once and a blind fixed offset risks landing on top of it.
- **`CanvasActivityPanel`, the text activity log**, is reached for what the
  object count cannot show: that a move, a resize, or a reorder actually
  arrived on the client that did not make it, not only that the server's own
  row changed. It replaces the drawing surface while open, so it is toggled
  on, read, and toggled back off rather than left open.

Drawing, moving, resizing, reordering and placing a note or shape all still
need `gestures(True)` and raw pointer events, the same as the react button -
a note or a shape places on pointer-down alone, so a one-point `drag()` call
is a real tap; the pasted image goes through the same `paste` DOM event a
real Ctrl+V produces (`e2e_js.paste_image`), not the API, because the bug
this scenario exists to catch was a client-side hydration gap that calling
the API directly would never have exercised.

**Not covered, deliberately: the in-flight stroke preview** a second client
sees while the first is still drawing (`canvas_stroke_preview_relay.dart`).
It paints through a second `CustomPainter` with nothing in the accessibility
tree at all, not even during the gesture, so proving a frame reached the
other browser mid-draw would need either a pixel comparison (this harness is
label-driven by design) or sniffing the receiving browser's own WebSocket
traffic over CDP, which would only prove a frame arrived, not that it
painted anything. `draw_stroke_and_see_it_live` already checks the *result*
of a draw on both clients; the preview itself is named here as an honest gap
rather than a test that would pass whether or not it worked.

**Not covered, deliberately: whether the dock's own controls are reachable
by touch at a narrow width**, the class of bug #460's own commit message
names (an overflow menu that opened off-screen until it learned to open
upward, caught by a widget test rather than by a person). `e2e_js.click`
finds a labelled control and calls `.click()` on the DOM element directly;
that fires the framework's own tap handler regardless of whether the
element is actually visible or covered, so a scenario built the same way -
launch a browser at a phone width, click every dock label, assert each is
found - would pass whether or not a real thumb could reach it, which is the
class of false pass this file's own touch-reach tests were written against
once already (see this file's own history, and `CLAUDE.md`'s canvas
entries). `canvas_call_dock_touch_reach_test.dart` and
`canvas_tools_row_touch_reach_test.dart` are the real check: both drive
`tester.tap(..., warnIfMissed: false)`, Flutter's own hit-test, at 320
logical pixels, and assert a clipped control is unreachable until a real
drag reveals it. Widening this harness's browsers to a second, narrower
size would only add a scenario that cannot tell "found" from "reachable" -
an honest gap declined for the same reason the stroke preview above is.

## What it drives at the API, on purpose

Reporting and blocking live behind a context menu that opens on right-click or
long-press.
With the accessibility tree on, a synthetic pointer event cannot open it, so
this harness cannot reach it.
A screen reader can: `GestureDetector` publishes a long-press semantic action,
which VoiceOver and TalkBack surface, and a test guards that.
A keyboard-only user cannot, because the rows take no focus and no key opens
the menu.
So those two are driven at the API, and `scripts/lib/e2e_admin.py` says so in
its docstring rather than implying the UI path was exercised.
The underlying gap is recorded in `CLAUDE.md`; closing it would make the menu
reachable for keyboard users and for this harness in the same change.

Reply and "Reply in thread" sit behind the identical menu, so sending a reply
and opening a thread are the same substitution, made in `e2e_replies.py` and
`e2e_threads.py` for the same reason; each says so in its own docstring.
Everything downstream of the send or the open - the rendered quote, its tap
target, a deleted parent's honest placeholder, the channel list's exclusion of
a thread, and the parent message's own reply-count affordance - is an ordinary
`Semantics` node with no menu behind it, so all of that is driven and checked
through the real UI.

Permissions are checked at the API deliberately rather than reluctantly.
Hiding a button is not access control; refusing the request is, and each body
sent is one an administrator would succeed with, so the only thing left to
explain a refusal is the caller.

## Reading a red run

Every scenario that needs a rendered channel fails the same way - a label that
never appeared - whatever the real cause was, because a browser gives a script
no other symptom.
So the first red run on a GitHub runner (30565517095) came back as nine
failures cascading from the first messaging one, and the screenshot showed a
signed-in client with a full member pane, an empty rail reading "Could not load
channels.", and the connection bar reading "Offline, retrying."

That is one cause, not two: the rail renders from the local database and sync
cannot start without it, so both die together when `WasmDatabase.open` throws.
It threw because `sqlite3.wasm` and `drift_worker.js` are gitignored and had
never been fetched on that runner, while every checkout here has had them since
before the workflow existed.
Sign-in, `/users` and the settings screens all kept working throughout, which is
why the run looked like a messaging bug rather than a missing file.

Three things came out of that and are worth knowing when the next one goes red:

- The harness fetches those two files and refuses to run if the served origin
  does not answer for them, so this particular failure is now a named refusal in
  the first few seconds rather than nine timeouts twelve minutes in. That check
  caught a second thing on its first run: `flutter build web` copies `web/` into
  `build/web` once and never re-syncs a file that turns up in `web/` afterwards,
  so `E2E_REBUILD` removes `build/web` before building.
- It refuses to start if something is already listening on the web port. A
  second server answers with a build this run did not compile, which is exactly
  what would have hidden the fault from a local reproduction. That refusal found
  where the stale ones came from: the static server ran inside a subshell, so
  teardown killed the wrapper and orphaned the server. It has no subshell now.
- The browser's own log is written beside each failure screenshot, and the
  workflow uploads the server log with them. The 404s were the whole answer here
  and nothing was capturing them.

## What it found

Running it against the real product, rather than reasoning about it, turned up
two defects nothing else had.

The avatar crop sheet sized its square viewport from the window's width alone,
so on any window wider than it is tall - which is every desktop - the circle
was taller than the screen and pushed Cancel and Use picture off the bottom.
There was no way to finish or abandon a crop, and so no way to set an avatar at
all. Fixed, with a test that asserts both buttons sit inside the window at
three sizes.

The context menu is unreachable without a pointer, described above. Recorded,
not fixed.

Driving the Voice Canvas for the first time found two more, neither of which
any widget test had caught, because neither needed a widget test to be wrong -
they needed two clients, or a client that never moved its camera.

Pasting an image onto the canvas did nothing, silently, whenever the composer
had ever held focus in the same session (which is every real session, since
signing in lands on a channel with a composer already there). Both the
composer and the canvas share one module-level "who is listening for a
paste" variable with no notion of ownership, and the composer's own
`dispose()` calls `stopClipboardImagePaste()` unconditionally; if that call
lands *after* the canvas's own `start()` already took over - which a fade
transition makes likely, not just possible - it tore down the canvas's
listener instead of its own. `stopClipboardImagePaste` now takes the same
callback `start` was given and only tears down while it is still the
registered one.

Undoing an erase or a clear did nothing visible on the client that clicked
Undo, unless that client happened to pan the camera afterward. The object
comes back server-side immediately - confirmed by reading `GET
.../canvas/ops` directly - but the client deliberately never re-materializes
a restored object's payload locally (it was freed on removal), and the
camera-move guard that would otherwise re-fetch it only runs when the view
actually changes. A full reload "fixed" it in testing only because a fresh
pane's very first camera-moved call always cold-fetches regardless of that
guard, which is what made this easy to not notice. Both `CanvasSync`'s
catch-up path and the live dispatch's `CanvasObjectsRestored` case now
force an explicit re-fetch alongside forgetting the tombstone.

## What it does not cover

The mobile clients, push notifications, search, polls, pinning,
invites beyond the one the seed spends, and message edit and delete.
Those are honest gaps rather than assumed-working: the run reports only what it
checked.
