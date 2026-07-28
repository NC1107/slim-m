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
up as well.

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
| reporting, blocking | the API (see below) | the moderation queue, the block list |
| permissions | the API | that a member is refused and an admin is not |
| a voice call, mute, leaving | the UI | the SFU's participant and track list |
| sharing a screen | the UI | a `SCREEN_SHARE` track on the SFU |
| edit, delete, search, pins, polls, invites, DMs, channel admin, devices, read state, sync | the API | the effect of each, not its status code |

The run ends by reporting how many documented API paths it actually touched,
counted from what the harness and both browsers requested rather than from a
list kept by hand, since a hand-kept list overstates coverage the moment a
scenario changes. A full run currently reaches **36 of 59** documented paths.

What it does not reach divides into three: routes that need a second
deployment or real hardware (push, the relay lifecycle, account recovery),
routes for features that are not built yet (the canvas), and routes that are
simply not covered yet (per-channel overwrites, assigning a role to a member,
kicking someone from a call, revoking one device, custom emoji, redeeming a
second invite). The last group is the honest backlog; the run prints it every
time so it cannot quietly grow.

## Layout

| File | What it owns |
| --- | --- |
| `scripts/e2e.sh` | the stack: SFU, server, web build, two browsers, teardown |
| `lib/e2e_run.py` | the running order, and the coverage report at the end |
| `lib/e2e_client.py` | one browser, over the Chrome DevTools Protocol |
| `lib/e2e_js.py` | the browser-side half: reading and driving the semantics tree |
| `lib/e2e_labels.py` | every accessible name the app is driven by, in one place |
| `lib/e2e_api.py` | the server's own answer, for checking against |
| `lib/e2e_messaging.py`, `e2e_settings.py`, `e2e_admin.py`, `e2e_voice.py` | the scenarios |
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
  and taking the last match opened the manage sheet every time.
- **The file picker's `<input>` never enters the document.** Flutter builds it,
  clicks it, and drops it, so there is nothing for `DOM.setFileInputFiles` to
  find; `createElement` is wrapped to catch it, and it is handed a real `File`
  through a `DataTransfer`.
- **Pointer events do not reach the canvas while the tree is on**, because the
  semantics elements sit over it. `gestures(True)` lifts them for the one
  affordance that has no label - the react button, which only exists while the
  pointer is over a message.

## Two things it drives at the API, on purpose

Reporting and blocking live behind a context menu that opens on right-click or
long-press and offers nothing else.
With the accessibility tree on, a synthetic pointer event cannot open it - and
neither can a person who does not use a mouse, because there is no keyboard
affordance and no semantic action.
So those two are driven at the API, and `scripts/lib/e2e_admin.py` says so in
its docstring rather than implying the UI path was exercised.
The underlying gap is recorded in `CLAUDE.md`; closing it would make the menu
reachable for keyboard users and for this harness in the same change.

Permissions are checked at the API deliberately rather than reluctantly.
Hiding a button is not access control; refusing the request is, and each body
sent is one an administrator would succeed with, so the only thing left to
explain a refusal is the caller.

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

## What it does not cover

The mobile clients, push notifications, the canvas, search, polls, pinning,
invites beyond the one the seed spends, and message edit and delete.
Those are honest gaps rather than assumed-working: the run reports only what it
checked.
