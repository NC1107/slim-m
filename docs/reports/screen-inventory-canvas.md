# Screen inventory: Voice Canvas

Part of [screen-inventory.md](screen-inventory.md).
"Surfaces harness" = `client/packages/app/test/ui_snapshot_test.dart`. See [screen-inventory-voice.md](screen-inventory-voice.md) for calls; the canvas can be open standalone or combined with a live call.

The canvas is never a route: `ConversationPane` substitutes `CanvasPane` for the whole conversation body whenever `canvasOpenProvider` equals the channel id.

## Top-level open/closed

- **canvas-closed** — default; `CanvasOpenButton` unlit; the button itself is entirely absent for a DM (DM base permissions lack `USE_CANVAS`). Coverage: implicit whenever a non-canvas surface is captured.
- **canvas-open-standalone-no-call** — pane mounted, `callDockDataFor` returns null so the dock shows tools only, no call controls. Coverage: covered (`canvas` surface, `c-general`).
- **canvas-open-during-call** — the dock combines `CallControls` and `CanvasToolsRow`, side-by-side at or above compact width, stacked below it. **Coverage gap worth flagging deliberately**: the `canvas-voice` surface forces `canvasOpenProvider` open on `c-main` but applies **no** `voiceControllerProvider` override, so `callDockDataFor` most likely still reads as not-connected — despite its name, this surface probably does not actually render the combined call+canvas dock. There is no surface anywhere that forces both providers together in the same channel. This is the single highest-value gap in the whole inventory to close with a real capture.

## Loading / error / truncation banners (`CanvasPaneBody`)

- **canvas-loading** — empty surface, `Semantics(label: 'Canvas, loading')`. Coverage: none confirmed (may settle before any captured frame).
- **canvas-error-forbidden** — "The canvas is not available in this channel." Coverage: none.
- **canvas-error-generic-load** — "The canvas could not be loaded." Coverage: none.
- **canvas-error-draw-forbidden-timeout-freeze** — "You cannot draw on this canvas right now." This is the visible face of the server's timeout freeze: `place`/`move`/`reorder` are blocked, `remove`/`clear`/`restore` are deliberately exempt, so the eraser keeps working while this banner shows for the pen. Coverage: none.
- **canvas-error-full-canvas** — "This canvas is full, or that id is taken." / "This canvas is full." (two call sites, slightly different copy). Coverage: none.
- **canvas-error-too-large** — "That stroke was refused as too large." / "That was refused as too large." Coverage: none.
- **canvas-error-erased-mid-save** — "That stroke was erased while it was being saved." Coverage: none.
- **canvas-error-image-decode-failed**, **-upload-failed**, **-refused**, **-paste-failed** — four distinct image-specific messages. Coverage: none.
- **canvas-truncated** — "Some ink in this region is not shown. Zoom in to see it." Reach: viewport page had more to give (`hasMore`). Coverage: none.
- **canvas-empty-hint** — "Nothing on this canvas yet" overlay. Reach: `document.objectCount == 0 && !loading`. Coverage: plausibly incidental in the covered `canvas`/`canvas-voice` surfaces if the fixture canvas starts empty, not deliberately proven.

## Activity log panel (toggled from the overflow menu)

- **canvas-surface-mode** — default; drawing surface mounted, all five tools in the dock. Coverage: covered (default state of both canvas surfaces).
- **canvas-activity-log-open** — drawing surface entirely unmounted, presence face-pile hidden, only undo/overflow/close remain in the dock. Coverage: none — nothing forces this open in either harness.
- **activity-panel-empty** — "No canvas activity yet." Coverage: none.
- **activity-panel-populated** — summary header ("N objects: X strokes, Y images, Z notes, W shapes") + list, newest first. Coverage: none.
- **activity-panel-entry-actor-disclosed**, **-actor-withheld** — see [screen-inventory-moderation.md](screen-inventory-moderation.md) for the full withheld-actor detail. Coverage: none.
- **canvas-activity-announcer** — screen-reader-only live region, not a visual state. Coverage: N/A.

## Note sheet

- **canvas-note-sheet-open** — bottom sheet, byte-capped multi-line field, "Add note" disabled until non-whitespace text exists. Reach: Note tool, tap to place. Coverage: none (not in the overlay harness's 21).

## Object context menu

- **canvas-object-menu-closed** — default, invisible hit-catcher. Coverage: implicit.
- **canvas-object-menu-open-own-object** — 3-item menu (bring to front / send to back / delete), anchored at pointer or object center depending on trigger. Coverage: none.
- **canvas-object-menu-mismatched-permission** — right-clicking someone else's object without `MANAGE_CANVAS` falls through to the empty-space menu below, the same as a genuine miss. Not a distinct visible state; noted so nobody expects a disabled menu here.
- **canvas-space-menu-open** — **added 2026-08-29, overriding this report's own prior finding below on direct owner request** ("no basic right click on canvas for quick actions"). Right-clicking empty canvas space now opens a 3-item pointer-anchored menu: paste image, add note, recenter view - each targeted at the exact world point clicked rather than the view's centre. Built as a second mode of `CanvasObjectContextMenu` rather than a new widget, so it inherits that file's own tap-up/hit-test-miss gating: a right-drag pan never opens it, and an object under the cursor always takes the object menu instead. "Clear canvas" is deliberately absent - see `canvas_object_context_menu.dart`'s own doc for why. Coverage: none (not in the overlay harness's 21).
- ~~**canvas-object-menu-empty-click** — clicking empty canvas space does nothing, deliberately no canvas-wide menu. Not a distinct visible state.~~ Superseded by **canvas-space-menu-open** above; kept struck through rather than deleted since this file's cross-reference section below still describes the harness's own coverage gap for it.

## Tool selection and pickers

- **canvas-tool-pen** (default, covered), **-note**, **-shape**, **-eraser**, **-select** — five mutually exclusive tool states in the strip. Coverage: only pen is covered.
- **canvas-tool-shape-kind-picker** — 4 shape-kind rows (rectangle/ellipse/line/arrow) appear in the overflow menu only while the shape tool is active. Coverage: none.
- **canvas-tools-row-fade-leading**, **-fade-trailing** — edge gradients once the tool strip has scrolled off one side, phone-width scenario. Coverage: none.
- **canvas-overflow-menu-closed**, **-open-with-conditional-items** — item set varies: always paste-image/recenter/activity-log-toggle; self-bubble toggle only while on this channel's call; per-hidden-tile "show" rows; shape-kind rows only with the shape tool active; bring-to-front/send-to-back/delete only with a selection; "Clear canvas" only with `MANAGE_CANVAS`. Coverage: none — the menu is closed by default in both covered surfaces, and none of the conditional combinations are exercised.
- **canvas-clear-confirm** — object-count-aware copy (singular vs "all N objects"). Coverage: none.

## Presence bubbles / camera tiles on canvas

- **canvas-presence-layer-empty** — nothing rendered, no call participants. Coverage: covered incidentally (the standalone `canvas` surface has no call).
- **canvas-camera-bubble** — camera-on participant, world-anchored, draggable/resizable. Coverage: none — needs voice participants combined with canvas open, which no surface does (same gap as `canvas-open-during-call` above).
- **canvas-camera-bubble-avatar-only** — camera off. Coverage: none.
- **canvas-screen-share-bubble** — a sharer's tile on the canvas itself. Coverage: none.
- **canvas-tile-locked** — resize grip hidden, drag/interact ignored, lock/depth/hide controls still reachable. Coverage: none.
- **canvas-tile-sent-to-back** — tile content moves behind `CanvasSurface` so ink draws over it; controls stay at the same screen position. Coverage: none.
- **canvas-tile-hidden** — locally hidden via tile controls, recoverable from the overflow menu's "Show <label>" row. Coverage: none.
- **canvas-tile-dragging-resizing-live** — transient in-flight gesture state. Not independently capturable as a still frame beyond what dragging shows.
- **canvas-self-bubble-hidden** — a persisted per-user preference hiding only your own camera bubble, never your screen-share tile. Coverage: none.
- **canvas-presence-roster-face-pile** — top-right avatar pile, hidden while the activity log is open. Known gap named in the code itself: a silent reader with the canvas open but not on the call and not moving a cursor is invisible here. Coverage: none.

## MANAGE_CANVAS-gated actions

- **clear-canvas-available**, **-unavailable** — the overflow item is present only with `MANAGE_CANVAS`, absent (never disabled) otherwise. Coverage: neither variant independently confirmed by either surface; the fixture's actual `MANAGE_CANVAS` grant was not verified by reading alone.
- **restore-canvas-affordance** — does not appear to exist as a distinct client control in the reviewed files; restoring a clear reads as server-only capability, with only the activity log's descriptive text for a `restore` op on the client side. Flagged for confirmation rather than asserted as certainly absent.

## Image paste

- **canvas-image-paste-idle** — no visible state, toolbar item always present, Ctrl+V/Cmd+V bound globally. Coverage: none.
- **canvas-image-paste-in-progress** — decode/upload/place sequence; no distinct loading UI found in the reviewed code. Coverage: none (and possibly nothing to capture between idle and an error/success state).

## Cross-reference: what the harness's `canvas`/`canvas-voice` surfaces do *not* show

Activity log panel, note sheet, object context menu, the empty-space context menu, camera/screen bubbles, locked/sent-to-back tiles, the timeout-freeze error banner, the truncation callout, an open overflow menu in any of its conditional shapes, any non-pen tool active, and (very likely, per the gap noted above) the combined call+canvas dock despite the `canvas-voice` name suggesting otherwise.
