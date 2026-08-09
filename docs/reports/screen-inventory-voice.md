# Screen inventory: voice calls (channel and DM)

Part of [screen-inventory.md](screen-inventory.md).
"Surfaces harness" = `client/packages/app/test/ui_snapshot_test.dart`. See [screen-inventory-canvas.md](screen-inventory-canvas.md) for the canvas, which can be open standalone or over a live call.

The old mic/camera pre-toggle lobby is gone; arrival auto-joins now (`voice_screen.dart`'s own doc comment), so most of the "join preview" states a naive reading of the product would expect no longer exist as a distinct pre-join screen.
The surfaces harness's `voice` entry hits a real, un-mocked controller against a fake HTTP client, so which specific non-connected state it lands on is not deterministic from reading the code alone — it is **not** the connected state, since nothing in that entry drives a real join.

## Non-connected states (`voice_join_preview.dart`)

- **voice-connecting** — spinner, "Connecting." Reach: `voice.state` is `connecting`/`joining`. Coverage: none deterministic (the `voice` surface may transiently show this but not on purpose).
- **voice-switch-prompt** — "Already in a call" / "Switching leaves it and joins this one instead," a switch button. Reach: connected or connecting to a *different* channel already. Coverage: none.
- **voice-rejoin-plain** — icon, roster, "You left this call," "Rejoin call." Reach: after an explicit hang-up, no recap worth showing. Coverage: none.
- **voice-rejoin-recap** — `CallRecapCard` in place of the plain text. Reach: a `CallRecap` scoped to this exact channel exists and is worth showing. Coverage: none.
- **voice-rejoin-error-retryable** — `AppErrorState` + "Try again." Reach: `voice.state == failed`, `retryable == true` (anything but 403/501). Coverage: none.
- **voice-rejoin-error-permanent** — same banner, **no retry button** at all. Reach: a 403 (permission denied) or 501 (no SFU configured). Coverage: none.
- **who-is-here-unknown** — renders nothing while the roster hasn't resolved. Coverage: none.
- **who-is-here-empty** — "Nobody is in this call yet." Coverage: none.
- **who-is-here-populated** — avatar row (first 8) + count text. Coverage: none.
- **voice-join-hides-button-on-permanent-error** — same as `-error-permanent` above, called out separately because it's a UI *absence* (no Join button at all) worth deliberately capturing rather than assuming.

## Connected states (`call_stage_layout.dart`, `call_participant_tiles.dart`, `voice_call_controls.dart`)

- **call-grid-no-share** — every participant as a wrapped tile, nobody sharing. Coverage: none — the fixture always has a sharer, so the plain grid never renders in the harness.
- **call-stage-with-filmstrip** — a fixed `ScreenShareStage` plus a scrolling filmstrip beneath. Coverage: covered (`voice-in-call`, phone-portrait/phone-landscape/desktop/compact bracket, both themes) — this is the one deterministic connected-call state in the whole app.
- **call-tile-camera-on-in-plain-grid** — a live camera feed in place of the avatar when nobody is sharing. Coverage: none (the harness's local participant has camera off, and the only camera-on participants are also inside the stage-with-filmstrip case).
- **call-header-error-banner** — `AppErrorState` above the grid/stage when `voice.error != null` mid-call. Coverage: none (fixture's error is always null).
- **local-screen-share-banner** — shown only when the *local* participant is the one sharing. Coverage: none (only a remote participant shares in the fixture).
- **call-tile-speaking-ring** — pulsing avatar ring. Coverage: covered as a static frame (Ada, `isSpeaking: true`); the pulse motion itself is not something a still screenshot proves.
- **call-tile-muted-badge**, **-unmuted-accent-badge**, **-screen-share-badge** (wins over the mute badge) — Coverage: all three covered (Bob muted, Nick unmuted, Ada sharing).
- **call-tile-camera-on** — Coverage: covered (Ada, Bob).
- **call-tile-expand-fullscreen** — `showFullscreenVideo` overlay from the expand button. Coverage: none, interaction-only.
- **call-controls-mic-on**, **-off** — Coverage: only one state per participant is shown at a time; both values exist across the fixture's three participants but the *local* control row's own toggle state is effectively the "on" case only.
- **call-controls-camera-toggle-with-switch-button** — the camera-switch control appears only when the local camera is on. Coverage: none (local camera is off in the fixture).
- **call-controls-camera-switch-in-flight** — spinner replacing the switch icon. Coverage: none.
- **call-controls-share-idle**, **-active-lit**, **-pending-awaiting-broadcast** (spinner, "Waiting for you to start the broadcast. Tap to cancel," deliberately not drawn as active) — Coverage: only `-idle` is implicit (local user isn't sharing); the other two are not covered.
- **call-controls-leave-button** — always present, destructive/outlined. Coverage: covered.
- **camera-source-sheet**, **screen-source-sheet** — device pickers. Coverage: covered by the overlay harness (generic instance, not from within a live call).

## Disconnect / error copy

Four distinct causes collapse to the same `VoiceRejoinScreen` error path (`-error-retryable` above), each with its own message but none individually distinguished by any test:

- **disconnect-replaced-by-other-device** — "You joined this call from another device, so this one left it."
- **disconnect-removed** — "You're no longer in this call." (covers a moderator kick, room deletion, or the server's stale-heartbeat sweep — deliberately non-specific).
- **disconnect-connection-lost** — "The call disconnected and could not reconnect."
- **disconnect-unknown** — "The call ended unexpectedly."
- Coverage: none of the four.

## DM call

- **dm-call-button-hidden** — channel not loaded, not a DM, or the self-DM. Coverage: none.
- **dm-call-button-idle**, **-active-lit** — Coverage: none.
- **dm-call-pane-open** — a 52px bar (name, dismiss) over an embedded `VoiceScreen(isDm: true)`, replacing the whole conversation body. Internally renders whichever non-connected/connected state above applies, with DM-specific copy ("Call" not "Voice channel"). Coverage: none — there is no DM route anywhere in the surfaces harness.
- **dm-call-pane-closed-call-still-live** — closing the pane only hides it; the controller keeps running, producing the strip/rail-summary states below. Not itself a distinct visual state.

## Collapsed / elsewhere indicators

- **voice-strip-hidden** — nothing rendered unless connected. Coverage: none (nothing to capture).
- **voice-strip-visible-compact** — bottom-pinned bar (avatars, name, duration, sharing/audio-only caption, mic/deafen/back/leave), compact width only. Coverage: none — the harness never combines a connected VoiceState with a route other than the call's own channel at a narrow viewport.
- **rail-call-summary-wide** — the same information folded into the rail footer at medium/expanded width. Coverage: none, same reason as above.
- **call-back-navigation** — not a visual state, a transition (sets `dmCallOpenProvider` if applicable, navigates to the channel).

## Cross-reference: what the harness's `voice-in-call` surface does *not* show

Explicitly, for anyone planning capture order: local camera on, the plain no-share grid layout, awaiting-broadcast/pending share, local mic-off, deafened icon, the mid-call error banner, the local screen-share banner, the collapsed strip or rail-summary "elsewhere" states, and more than three participants.
