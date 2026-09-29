# 0043 - A scene declares its motion; the client plays it

Status: accepted
Date: 2026-09-29

## The ask

Every module frame is a round trip a person caused.
A module cannot say "and then, a moment later, draw this", so nothing it renders can move.
Found by writing `music-box`: it plays a tune but its grid has no playhead.
The owner's standing direction on the scene contract is "I'd like to not be the limitation for what people want to run".

## Why this is not just another op

Every op so far is inert: the client reads it and paints.
Anything that makes a module act after nobody asked lets a posted message spend a reader's battery and CPU.
Decision 0027 answered the sound version by tying it to the viewer's own action.
Motion has no such hook, so the bound has to be in the shape of the feature.

## Options

1. **Declared motion inside one frame.**
   An op carries a `sweep`: where it ends up relative to where it is drawn, and how long it takes.
   The client interpolates.
   No module call happens, so cost is fixed by the numbers in the scene.
2. **A bounded re-run.**
   The scene asks for N more frames at an interval, and the client calls the module each time.
   Covers a running automaton, which shape 1 cannot.
   Each call is a sandbox run per viewer, for a person who only scrolled past, and the shared route stores and broadcasts every result.
   It needs a budget the client and the server both police, plus visibility tracking to stop it off screen.
3. **A free-running tick.**
   Rejected: nothing bounds what a posted message costs a reader.

## Decision

Ship option 1 now.
Do not ship option 2 until a module needs it and the visibility signal exists.
`play` already covers the "keep stepping" case, and it is bound to the viewer pressing it.

Shape 1 covers a playhead, a progress bar, a slide-in and a countdown, which is what the card found missing.
It does not cover a scene whose next state depends on module logic.
That stays a control press or `play`.

## The contract

`sweep` is accepted on `rect`, `circle`, `line` and `text`.
On any other op it is ignored.

```json
{ "op": "rect", "x": 4, "y": 12, "w": 3, "h": 68, "sweep": { "dx": 149, "secs": 2 } }
```

- `dx`, `dy` move the op.
  `dw`, `dh` grow a rect's width and height, or a circle's radius (`dw`).
- `secs` is the duration and `delay` the wait before it starts.
- Motion is linear, runs once, then holds at the end.

## The ceilings

Enforced independently by the client (`module_scene_sweep.dart`) and by the server before a shared scene is stored (`http/scene_limits.rs`).
The client cannot trust the server, since a scene also arrives from Dock runs and older servers, and the server does not trust the client to be the only line.

- `secs` is at least 0.1 and `delay + secs` at most 10 seconds.
  The whole scene stops moving after 10 seconds.
- 8 animated ops per scene.
  Later ones draw still, at their declared geometry.
- Deltas are clamped to plus or minus 10000 and non-finite numbers are treated as absent.
- Numbers are clamped, never refused, like the rest of the contract.
  The server only rewrites a scene that mentions `sweep`, and leaves anything it cannot parse for the client to reject.

## Where the bound holds

- **Shared scene.**
  Each viewer runs their own clock, once per frame received.
  A frame is already what the run route's rate limit meters, so a sender cannot restart motion faster than that.
  No viewer's clock causes any traffic.
- **Backgrounded app.**
  The clock stops on any lifecycle state other than resumed and does not replay on return.
- **Off screen.**
  Flutter skips painting a widget outside the viewport, so a sweep costs a tick and no raster.
  It also ends by itself within 10 seconds.
  A `TickerMode` that is off (a covered route) mutes the ticker.
- **Reduced motion.**
  The end state is drawn straight away, with no clock.
- **Sound.**
  Unchanged.
  A `sweep` never plays anything, and `notes` keeps its 0027 rule.

## Known limits

- A `tap` on a swept op hits the geometry it was declared with, not where it currently is.
- Only the ops above move.
  `cells` and `path` do not, so a moving grid is drawn with rects for now.
- Option 2 is not built.
  If it is, it needs its own record: a per-frame re-run budget, and a viewport signal in the client.
