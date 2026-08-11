# Voice screen review - merged

Three independent lenses (frontend implementation, UX/accessibility, backend/contract) reviewed the same screenshot set and code paths, merged here per screen.

## What this covers

Screens: `voice` (plain join-arrival), `voice-connecting`, `voice-in-call` and its six state variants (grid, local-camera, local-share, mic-off, share-pending, error), `voice-rejoin-plain`, `voice-rejoin-recap`, `voice-rejoin-error-retryable`, `voice-rejoin-error-permanent`, `voice-switch-prompt`, `who-is-here-empty` / `-populated` / `-unknown`, and `dm-call`.
16 screen states, each captured across desktop, phone-portrait, and a subset across phone-landscape and tablet-portrait, in both themes - on the order of 60 individual PNGs.

## The short version

- The floating call dock's shadow paints as a flat opaque grey bar in these captures; this is a known rasteriser limitation, not a UI bug, and it has now fooled two separate review passes.
- ~~`who-is-here-unknown` renders nothing at all for a state the code deliberately defines as ambiguous between "no voice configured" and "SFU unreachable" - the ambiguity is a documented, reasoned trade, but rendering it as a blank gap is not.~~ Fixed 2026-08-10.
- ~~The recap card on `voice-rejoin-recap` sits directly under a present-tense "Nobody is in this call yet." sentence with nothing marking it as a summary of the call that just ended.~~ Fixed 2026-08-10.
- ~~The eject-from-call button is gated on deployment-wide permissions client-side while the server enforces it per-channel - the third instance of this exact mismatch shape found across this review.~~ Already closed on main before this pass (PR #523); see Cross-cutting below.
- ~~`voice-in-call-share-pending` explains itself only through a hover/long-press tooltip, with no on-screen text for a touch user watching the button change.~~ Fixed 2026-08-10.
- Everything else in this set - icon-vs-colour state carrying, error copy, the three rejoin states, the switch-prompt, DM call framing - reads correctly and was checked against source, not just eyeballed.

## voice (plain join-arrival)

Verdict: unreviewable as captured, and confirmed to be a closed capture-harness gap rather than a product bug.

See Cross-cutting for the full account (both the frontend and UX lenses hit this independently and it is resolved below).

## voice-connecting

Verdict: correct, both viewports and themes.
Centred spinner plus "Connecting" label, no overlap with the offline banner where present.
No findings (frontend, UX).

## voice-desktop-narrow / voice-tablet-portrait

Verdict: same closed capture-harness gap as `voice` above, not a separate finding.
See Cross-cutting.

## voice-in-call

Verdict: stage-plus-filmstrip layout reads as one call, not three boxes.
State (mic/camera-off, screen-share badge, speaking) is carried by icon shape in addition to colour throughout.
No product findings.

- The apparent hard-edged grey bar under the dock, found independently by both the frontend and UX lenses, is a capture-rasteriser artifact, not a UI defect.
  See Cross-cutting for the full explanation; it is not re-listed as a finding on this or any other in-call screen.
- Low, cosmetic: `CallDuration._format` (referenced against the fixture's duration text, "3 in call - 73:35:05") uses bare `d.inHours` with no day rollover, so a call running past 24 hours reads as a 73-hour clock rather than something like "3d 01:35:05."
  Unlikely in practice (the fixture's `connectedAt` is set far in the past to exercise this), but worth a day-aware format if multi-day uptime is ever a real scenario (UX).

## voice-in-call-grid / voice-in-call-local-camera / voice-in-call-local-share / voice-in-call-mic-off / voice-in-call-error

Verdict: each correct, both viewports/themes, no findings beyond what is already recorded once under `voice-in-call` (frontend, UX).

- `voice-in-call-local-share`: `LocalScreenShareBanner` (an accent-tone `AppCallout`, not a raw container) is visible above the stage on both viewports, correctly distinguishing the caller's own outgoing share from someone else's (frontend, UX).
- `voice-in-call-mic-off`: three independent surfaces (participant-tile badge, dock mic button, account-row mic glyph) all flip icon shape, not colour alone (frontend, UX).
- `voice-in-call-error`: "Lost the connection to Ada. Reconnecting." names who, states what, no blame, no jargon; outlined danger banner matches the project's rule that danger is never a filled surface (frontend, UX).

## voice-in-call-share-pending

Fixed 2026-08-10, per the "Fix" line below: a new `LocalScreenSharePendingBanner` (a distinct `AppCalloutTone.info`, never the active-share accent tone) renders in `call_stage_layout.dart`'s `awaitingBroadcast` branch, in the same slot `LocalScreenShareBanner` already occupies for a live share.

Verdict: functionally correct, but the only on-screen signal that a system picker is waiting for a response is a bare spinner glyph swapped into the share button, with no visible text anywhere on screen.

- What's wrong: `_ControlButton`'s `pending` state (`voice_call_controls.dart:262-272`) replaces the share icon with a `CircularProgressIndicator`, and the only explanation is the button's `Tooltip` ("Waiting for you to start the broadcast. Tap to cancel.", `voice_call_controls.dart:128-131`), reachable only by desktop hover or a mobile long-press.
  `LocalScreenShareBanner`'s own doc comment (`local_screen_share_banner.dart:12-15`) deliberately declines to show its "You are sharing your screen." banner for this state, reasoning that would be "the exact lie that field exists to stop" - a correct call, but nothing on-screen was put in its place (frontend, UX, found independently).
- Evidence: `voice-in-call-share-pending-desktop-dark.png`, `voice-in-call-share-pending-phone-portrait-dark.png` - no banner, no caption, only the small spinner in the control row.
- Fix: surface the tooltip's own sentence as a second, distinct-tone `AppCallout` for exactly the `awaitingBroadcast` window, in the same `call_stage_layout.dart:80-84` slot that already conditionally renders `LocalScreenShareBanner` - one more branch generalises it.
  A neutral or dedicated "pending" tone, never the active-share accent tone, so the two states stay visually distinguishable.
- Severity: medium.
  This is a real system picker the user has to go answer, and nothing above button-size says so on a touch device with no hover.

## voice-rejoin-plain

Verdict: correct, both viewports/themes.
"Voice channel" / "Nobody is in this call yet." / "You left this call." / "Rejoin call" reads as four short, sequential, unambiguous facts before one clear action, with no roster shown (nobody there) (frontend, UX).

- Component-conformance finding, shared with `voice-rejoin-recap`, `voice-rejoin-error-retryable`, and `voice-switch-prompt`: `VoiceRejoinScreen` and `VoiceSwitchPrompt` build their primary action with a raw `FilledButton`/`FilledButton.styleFrom`, hand-setting `backgroundColor: tokens.accentFill`, `foregroundColor: tokens.accentOn`, and padding (`voice_join_preview.dart:88-96`, `188-200`), instead of `AppButton(variant: AppButtonVariant.primary, full: true, ...)`, which already produces the identical look (`design_system/.../button.dart:66-72` uses the same two tokens) plus the shared component's focus ring, press feedback, and semantics handling.
  Fix: replace all four call sites with `AppButton`.
  Severity: medium (frontend).

## voice-rejoin-recap

Fixed 2026-08-10, the first suggested fix: `CallRecapCard` now carries its own "Your last call" label above the stats row.

Verdict: the stats themselves are correct and match a purely local, no-server-round-trip computation, but the card visually contradicts the sentence sitting directly above it.

- ~~What's wrong: the screen reads "Nobody is in this call yet." (present tense, correctly describing the now-empty call) immediately followed by a card showing "18 min / in the call," "1 / other person," and an avatar row naming "Ada," with nothing on the card marking it as a summary of the call that just ended.
  `call_recap_card.dart` has an optional "left early" caption for a participant who departed before the caller did, but when nobody left early (as in this fixture) the participant row renders with no caption at all, so nothing distinguishes "this describes the call that just ended" from "this is who is currently in the call."
  A first reading is very likely "wait, is Ada still in there or not?" (UX).~~
- Confirmed against source as correctly local: `CallRecap`/`CallActivityTracker` (`providers/call_recap.dart`) is built "entirely from the roster a live call already reports - no new server state" (file header) and never asks the server for anything, so the numbers themselves are trustworthy - the finding is presentation, not data (backend).
- Evidence: `voice-rejoin-recap-desktop-light.png`, `voice-rejoin-recap-phone-portrait-light.png`.
- Fix: give the card its own label, e.g. "Your last call" or "How it went," above the stats row, or restore the "You left this call." line (present on `voice-rejoin-plain` but dropped here) directly above the card so the sequence reads empty-now, you-left, here's-the-recap.
- Severity: medium-high.
  This is the screen landed on every time a call is left with a recap available, so the ambiguity recurs rather than being a one-off (UX).
- Same shared `AppButton` conformance note as `voice-rejoin-plain` applies to this screen's rejoin button (frontend).

## voice-rejoin-error-retryable

Verdict: correct.
"The call disconnected and could not reconnect." plus a clear "Try again" button, matching `retryable: true` on the two generic/unexpected-exception branches in `VoiceController.join` (`voice_controller.dart:192-207`) - a transient condition, not one of the server's two named-permanent answers (frontend, UX, backend).
Same shared `AppButton` conformance note applies (frontend).

## voice-rejoin-error-permanent

Verdict: correct, and this is the important one to get right: no button of any kind is rendered.
Confirmed against `voice_screen.dart:187` (`if (canRetry) FilledButton(...)` with nothing in the `else` branch) - the button is genuinely absent, not disabled - and against the server side: `retryable: false` is set only for `NotConfiguredException` (501) and `ForbiddenException` (403) (`voice_controller.dart:178-191`), the server's two genuinely non-retryable answers for `POST .../voice/token` (`voice.rs:134-139`, `:118-120`).
A retry against either is guaranteed to repeat (frontend, backend, found independently and confirmed consistent).

- Low, cosmetic: the heading above the error still reads "Voice channel / Nobody is in this call yet." - accurate but beside the point when the real news is "you can't join," costing an extra beat before the actual answer.
  Not worth a fix on its own (UX).
- Consistency note, not a bug: the roster line stays "Nobody is in this call yet." underneath a permission-denied error because the roster route only requires `VIEW_CHANNEL` (`voice.rs:237-239`) while the token route requires `VIEW_CHANNEL ∪ CONNECT` (`voice.rs:117`) - a caller who can see the channel and its roster but cannot connect is a real, reachable state, e.g. `CONNECT` denied by a channel overwrite while `VIEW_CHANNEL` stays granted (backend).

## voice-switch-prompt

Verdict: does the one thing this screen exists for well.
"Already in a call" / "You're in a call somewhere else. Switching leaves it and joins this one instead." states the consequence before the button, in plain language - the strongest copy in this set (UX).
On phone, the minimized call strip correctly renders at the bottom in place of the ordinary account row while busy elsewhere ("In a call - audio only") (frontend).
`_busyElsewhere` is entirely local `VoiceController` state and the copy asserts nothing server-side that isn't true of `leave()`/`join()` (backend).
Same shared `AppButton` conformance note applies to "Switch to this call" (frontend).

- Low, likely fixture gap: the persistent mini call-status row at the bottom-left of the rail - exactly where a person would look to confirm what they're about to leave - reads "a call" / "- in call" rather than a real channel name and duration.
  `rail_call_summary.dart`: `'a call'` is a literal fallback used only when the local channel list has no row for that channel id, and the leading `" - in call"` is meant to trail a `CallDuration` widget not rendering here (no `connectedAt` in this fixture), leaving an orphaned fragment with a stray leading dash.
  Fix: re-capture with a seeded channel name; if the fallback is ever hit for real (e.g. a channel deleted mid-call), consider tightening "a call" to "the other call" so it doesn't read as a placeholder.
  Severity: low, but flagged because it degrades exactly the row that should be checked before confirming a destructive-ish action (UX).

## who-is-here-empty

Verdict: correct.
"Nobody is in this call yet." only renders for the genuinely-checked-and-empty case - confirmed the roster value actually arrived rather than being unset (`voice_join_preview.dart:230-236`, `voice.rs:271-282`, `roster.rs:44-45`).
Matches the server, matches the screen (frontend, UX, backend).

## who-is-here-populated

Verdict: correct.
Avatars plus "X, Y are here," with a screen-reader-only pluralised label distinct from the visible text; confirmed the names come from the real `RosterParticipantDto` list and that the caller's own id is dropped client-side (`voice_roster.dart:65-69`) - load-bearing, not redundant, since the server only drops *hidden* others, not the caller (`voice.rs:284-296`) (frontend, backend).

- Low, suspected, nothing wrong found: appear-offline for this preview is enforced by the server dropping the hidden participant entirely before the DTO is built, so there is no in-between rendering to check and the fixture set has no hidden-user case exercised - noted only as the one behaviour in this file the screenshots structurally cannot verify (backend).

## who-is-here-unknown

Verdict: fails the "each of the three roster answers must say something true and different" bar as rendered, even though the underlying ambiguity it is failing to explain is a deliberate, documented design trade rather than an oversight.

- The collapse itself is reasoned, not accidental: the roster route gives three distinct server answers (501 not-configured, 503 unreachable, 200 empty), and `voiceRosterProvider`'s own doc comment (`voice_roster.dart:44-50`) is explicit that "not known yet" is deliberately what both "no SFU configured, ever" and a persistently-unreachable SFU render as - `tick()` only special-cases `NotConfiguredException`, and every other `ApiException`, including a 503 that never recovers, falls into "try again next tick" with the stream never emitting a value.
  This half is not a bug (backend).
- ~~What is a finding: `_WhoIsHere` implements that "don't know yet" case as `if (roster == null) return const SizedBox.shrink();` - rendering literally nothing, indistinguishable from a missing widget, a stalled load, or a layout bug.
  Confirmed by direct comparison: where "empty" says "Nobody is in this call yet." and "populated" names who's there, "unknown" leaves a gap where the roster sentence would be, jumping straight from the heading to "You left this call." (UX).
  Evidence: `who-is-here-unknown-phone-portrait-light.png`, compared against `who-is-here-empty-phone-portrait-light.png` and `who-is-here-populated-phone-portrait-light.png`.
  Fix: give this case its own true statement, e.g. "Can't tell who else is here right now," matching this project's plain, hedged register - this fixes the rendering without touching the reasoned collapse of the two server causes into one client state.~~
  Fixed 2026-08-10, that exact suggested copy: `_WhoIsHere` now returns `Text("Can't tell who else is here right now.")` instead of `SizedBox.shrink()`.
  If the collapse itself is ever revisited: surface a distinct "could not check who's here" state after N consecutive non-`NotConfigured` failures, rather than staying silent forever (backend). **Still open** - not attempted here.
- Severity: high for the blank-render half (confirmed against source, not inferred from the image alone); the collapse-of-two-causes half stays low/documented-intent and is not part of the severity rating.

## dm-call

Verdict: correct.
Phone-icon-plus-name header and plain "X" close button are visually distinct from a channel voice header (speaker icon, member-list toggle), correctly signalling a DM call rather than a text channel.
The speaking participant's avatar carries a visible accent ring (`AppSpeakingRing`) distinct from the shared mic-active badge - the clearest evidence in this set that the speaking indicator works (frontend, UX).
No participant-moderation affordance is shown on this screen, which is correct: nothing in `store/dms.rs` grants `KICK_MEMBERS` inside a DM channel's permission set, and the one DM-call-specific server behaviour (blocking evicts the blocked party, never the blocker) is not contradicted since no block/evict control is shown at all (backend).

## Cross-cutting

**The floating dock's shadow is a capture-evidence artifact, not a product finding, and it has now misled two review passes.**
Both the frontend and UX lenses independently traced a flat, hard-edged grey band bleeding off the bottom of every in-call and `dm-call` screenshot to `AppShadows.float` (`Color(0x85000000)`), and the UX lens's pixel measurement of the composited colour is correct.
The conclusion that this is a rendering defect is not: the offscreen rasteriser these harnesses use does not blur or alpha-blend a `BoxShadow`, so a soft, translucent, 64px-blur shadow paints as flat opaque black with a hard edge instead.
This is already documented in `client/packages/voice_canvas/test/visual/visual_render_support.dart`, which itself records that an earlier sign-off pass made the identical mistake.
Treat every "hard-edged grey bar under the dock" mention across this report's screen-by-screen sections as this same explained artifact, not as a separate defect per screen - it is not re-listed as a finding on any individual screen above.
Whether the real, blurred shadow renders correctly on a genuine device build is still worth a real-device check on general principle, but there is no evidence in this capture set that it doesn't.

**`voice`/`voice-desktop-narrow`/`voice-tablet-portrait` rendering blank is a closed evidence gap, not a reachable product state.**
Both the frontend and UX lenses independently flagged the plain `voice` join-arrival surface as rendering nothing at all below the header, across every viewport and theme sharing that fixture.
The cause is a capture-harness gap: `ui_snapshot_test.dart`'s `voice` entry renders the route with no `voiceControllerProvider` override and no extra settle pump, so it captures a transient sub-frame state during the `AppFadeIn` remount that follows the post-frame `controller.join()` call - the same "renders at opacity zero unless the harness pumps twice" trap this project's own history already names for other screens, and it is not something a real user could see for more than a few milliseconds.
It has been confirmed this is not a reachable failure mode: `VoiceController.join` always transitions to a terminal state (connecting, connected, or a specific failed state with a real message) rather than ever leaving the screen genuinely blank, so there is no product-side "user has no route forward" scenario hiding behind this gap.
Fix (tooling, not product): give the `voice` entry a pinned controller override or the same settle handling `voice-rejoin-*` already uses.
Severity: low, harness only - it removed three screen-state groups from what this review could verify at those specific breakpoints, but the equivalent real states (connecting, in-call, rejoin) are covered and correct elsewhere in this matrix.

~~**The eject-button permission-scope mismatch is the third instance of one root cause found across this review.**
`member_profile.dart:297,301-305` computes `canEject` from the caller's deployment-wide base permission bitmask (`myPermissionsProvider`, explicitly "base (deployment-level)" per `admin_providers.dart:25-29`), while the server's `POST .../voice/participants/{user_id}/kick` route is deliberately channel-scoped - its own doc comment says "Gated on `KICK_MEMBERS` in that channel, evaluated per channel rather than deployment-wide" (`voice.rs:303-305`), checking `permissions_in_channel` and `granted_permissions_in_channel`, never the base bitmask.
Concretely, in both directions: a moderator granted `KICK_MEMBERS` only via a channel overwrite on that one voice channel never sees the Eject button at all, even though the server would honour the kick; a member holding `KICK_MEMBERS` deployment-wide but denied it via an overwrite on that specific channel sees the button, taps Eject, and gets a 403 the confirmation dialog gave no reason to expect.
Neither is a security hole - the server is the real authority and enforces correctly either way - but it is a real affordance/action contract mismatch, not visible in any single captured screenshot since no member-profile popover is among the captured voice screens.
Fix: read a channel-scoped permission for `canEject` specifically, the way `canTimeOut` and `canRemove` are already correctly matched to their own deployment-wide-checked routes.
This is the same root-cause shape (a UI-side permission check scoped differently from the server route it gates) as findings recorded in `shell.md` and `settings.md`; see those reports for the other two instances.~~
Already closed on main, not part of this change: `member_profile.dart`'s `canEject` now reads `myChannelPermissionsProvider(voice.channelId!)`, part of the decision-0011 per-channel-permissions sweep (PR #523, see CLAUDE.md's "The client asked one permission question and the server answered a different one, in eight places," 2026-08-10) that landed before this pass started. Checked directly against current source rather than assumed stale.

**Icon-vs-colour state carrying is consistently strong across this entire surface.**
Mic, camera, share, and pending state all change glyph shape, not merely tint, everywhere checked: call controls, participant-tile badges, the account-row mic glyph, and the collapsed call strip.
No emoji anywhere in this surface; all icons are `AppIcons.*` (frontend, UX, found independently).

**`_ControlButton` is a near-total reimplementation of `AppIconButton`, kept apart only by one missing feature.**
`voice_call_controls.dart:198-280` duplicates `AppIconButton`'s touch sizing, `Tooltip` plus `Semantics(button: true)` pattern, `AppFocusRing` wrapping, and destructive/active colour logic, because `AppIconButton` has no `pending` (loading-spinner) state and the share/camera-switch buttons need one.
`AppIconButton` already supports `active` and `variant: danger`, so the actual gap is narrow: a `pending: bool` parameter (swap icon for a small `CircularProgressIndicator`, as `_ControlButton` already does) would let this file drop its own implementation entirely and inherit the shared component's focus/press/hover handling.
Severity: medium - not a visible bug today (the two implementations currently look identical), but a maintenance risk: any future tweak to `AppIconButton`'s interaction behaviour silently will not reach the four call-control buttons every voice screen shows (frontend).

**Roster/presence data sourcing is correct by design, with one likely-harness gap and one low-severity error-handling gap.**
The in-call roster ("3 in call") is drawn from the live SFU-derived `VoiceSession.participants`, not the `voice/roster` preview route, which is why the caller's own tile correctly appears in-call ("Nick (you)") even though `voiceRosterProvider` deliberately drops it in the preview - two different data sources by design, and the screens are consistent with each (backend).
Suspected fixture artifact, not a contract bug: every in-call screenshot's member pane shows all three members as "OFFLINE - 3" while two are simultaneously shown as live call participants in the main stage.
Presence and voice-call membership are genuinely independent signals server-side, so this is not something the server contradicts, but no presence override was found wired into the voice snapshot fixtures - flagged for whoever owns the harness, worth confirming a real client in a real call shows those participants as online (backend).
Separately, low severity: roster polling treats a genuine, permanent 403 (e.g. `VIEW_CHANNEL` revoked mid-preview) the same as a transient 503/429 - "try again next tick" - so a real permission revocation would leave a stale roster on screen rather than clearing or surfacing it, though this is likely unreachable in practice since losing `VIEW_CHANNEL` on a previewed channel should also remove it from the rail through the ordinary permission-cache path (backend).

**Correctness safeguards worth naming rather than flagging.**
`VoiceParticipant`'s `==`/`hashCode` and `VoiceSession._refreshParticipants`'s `listEquals` gate stop LiveKit's continuous audio-level event stream from forcing a full roster rebuild every frame, with the reasoning written into the code itself; combined with stateless tiles and tracks re-derived per build rather than cached, the "rebuild everything on every frame" failure mode this review specifically looked for is not present (frontend).
The heartbeat/sweep backstop is never claimed as instantaneous anywhere in the reviewed screens, consistent with `voice.rs`'s own doc comment that eviction, not a bare permission change, is what makes a kick or timeout take effect immediately rather than whenever a stale token lapses (backend).

**Minor items, not escalated.**
No scenario in this set shows an active speaking ring on the in-call grid/filmstrip screens (only `dm-call` happens to catch one participant mid-speech) - worth adding to a future capture pass so the speaking cue is not verified by accident in only one place (UX).
`CallParticipantTile`'s camera/screen-share letterbox background is a literal black rather than a token, checked and judged a defensible, common video-chrome convention rather than a missed token (frontend).
