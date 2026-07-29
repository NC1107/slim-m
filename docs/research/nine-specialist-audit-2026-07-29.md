<!-- SPDX-License-Identifier: Apache-2.0 -->
# The nine-specialist audit (2026-07-29)

Nine specialist reviews run in parallel over the same build: five over the code (server performance, database, Rust correctness, Flutter correctness, client performance) and four over screenshots of the running product (product design, a first-time end user, a Discord power user, accessibility).
The screenshot set was 13 captures from a live two-user e2e run plus the 20 static shell renders.
51 findings came back; every one acted on below was re-verified against the code before any fix, and two turned out to be artifacts (noted at the end).
This file is the single consolidated report; per-finding detail lives in the workflow transcripts.

## Fixed in this pass

**A peer's screen share was never rendered, anywhere.**
Three of the four screenshot auditors independently ranked this first, and it was found before they reported by reading the e2e's own captures: Alice shares, Bob is subscribed to the track at the SFU, and Bob's pane shows a glyph on a roster row and nothing else.
Publishing had been built and viewing never was.
`VoiceSession.screenShareViewFor` now returns the live view as a plain Widget (no LiveKit type crosses the rtc seam), and the call screen mounts it on a named `ScreenShareStage` above the roster.
Verified end to end: the re-run e2e's `bob-peer-sharing-screen.png` shows Alice's actual shared screen rendered on Bob's stage.

**Push fan-out multiplied the write path by the member count.**
Every message asked `has_permission` once per push-registered user, and each ask was four queries.
`viewers_among` batches the whole candidate set into a fixed number of queries and runs the same pure evaluator per candidate; an equivalence test proves the batched and per-user answers identical across every precedence rule, the ADMINISTRATOR bypass, DMs, and a nonexistent channel.
`push_targets` likewise became one `IN` query, and migration 0019 adds the indexes for scans that grow with content (the account-deletion anonymization UPDATEs, the attachment sweep's `created_at`, the token sweeps' `expires_at`).

**Two rtc landmines.**
`countScreenSources` enumerated Wayland windows, which segfaults the whole process; the sibling file avoided exactly this and the probe now matches it.
And overlapping `VoiceSession.join` calls raced one room slot and could strand the UI on connecting; they serialize now, with a two-concurrent-joins test.

## Chosen next, in order

1. Offline member rows fail WCAG AA: the wholesale `Opacity(0.62)` on a muted `AppListRow` drags already-minimum text below 4.5:1 (measured 3.7:1 light, 4.9:1 dark against 7:1 unmuted). Restructure so the label keeps a compliant colour.
2. In-call participant state (muted, sharing, speaking) is icon-only with no semantics; a screen-reader user in the flagship feature hears names and nothing else.
3. The composer placeholder uses `textDisabled` for an active input's hint, failing AA in every screenshot; `AppInput`'s own hint token is the fix.
4. Attachments render borderless with no filename or size, read as decoration rather than files (two auditors independently).
5. The roles screen's trailing icons re-pack per row (conditional delete button), so columns misalign.
6. "Invites" and "Who can join" share one icon in Space settings.
7. `GET /channels` is 1+4C queries for C channels; the caller's role context should load once.
8. A duplicated id in `attachment_ids` 500s instead of 400ing; the login decoy-hash path swallows `HashError::Busy`, weakening the timing defence it exists for.
9. The in-call screen reads as a debug list: tiles and a call-duration line, sized for the two-to-eight-person calls this product is for.

## Recorded, deliberately not this pass

**Protocol: edits and deletes made while a client is offline never reconcile.**
Edit does not advance `seq`, `/sync` filters purely by `seq`, and deleted rows are filtered out of deltas, so a client that was offline for either carries the stale row until a reset heals it.
This needs a designed answer (a per-channel op watermark or tombstone list in the sync response), not a patch, and it interacts with E2EE plans; it is the most important open correctness item in this report.

**WS fan-out cost.**
Every event still re-derives permissions per connected socket (four queries each); the hub is deployment-wide.
The safe fix is a per-connection visibility cache with real invalidation, which wants its own change with tests around role and overwrite edits taking effect immediately.

**Feature gaps a Discord group would hit weekly**, confirmed against BACKLOG.md so nothing deliberately declined is re-proposed: replies (the backlog reserves `parent_message_id` as a hook), camera video in calls, per-channel notification mute, per-user volume and push-to-talk, a mention-versus-ambient unread distinction on the rail, paste and drag-and-drop attachments, and free-text custom status.
Each is roadmap-shaped, not bug-shaped.

**Smaller recorded items**: resolved reports are retained forever (decide: sweep or document), the DM block answer may be inferable by the blocked party (wants a product decision), `list_dm_conversations` and `GET /presence` batch poorly, avatar and profile fetches re-fetch on scroll (wants a keep-alive grace), the voice roster's per-channel timers fire unjittered bursts, message tokenization re-runs per rebuild, "Notifications: not available on this device" is a dead end with no explanation, the "System never picks true black" caption reads as jargon, role cards show raw permission counts ("admin, 1 permission" reads as a bug), the offline banner offers no manual retry and the composer stays fully interactive while offline, and the channel-page transition keys make `ChannelScreen` doc comments describe a lifecycle the router no longer provides.

## Verified non-issues

The two mic icons "disagreeing" is the footer's correctly disabled state when not in a call (WCAG exempts inactive controls), though the endUser point that two mic glyphs coexist during a call stands as a design consideration.
The static renders' missing avatars are the snapshot harness's async-image limitation, matching its known reaction-chip gap; the live e2e captures show initials discs correctly.

## Round two: the screens the first round under-covered (same day)

The owner pointed out the first round's screenshot set skewed toward voice, so the snapshot harness grew from 2 surfaces to 12 (onboarding, sign-in, personal/space/voice settings, and all five admin screens, phone and desktop, both themes - 60 renders, all under the CI overflow gate now), and four specialists re-ran over the full set: settings/admin design, the first-run journey, accessibility, and a text-channel deep pass.
25 findings; fixed the same day:

- Raw exception text reached users: "Who can join" rendered a Dart type-cast error verbatim, and a sweep found 14 sites interpolating `$e` into visible copy (two of them showing the bare exception as the whole message). All now say a fixed human sentence; the object still reaches the log.
- The Roles screen's empty state was literally blank, and Devices rendered a bare header over nothing; both now say what they are, like their siblings.
- Sign-in greeted a fresh invitee with "Sign in": someone arriving with an invite code now lands on creating an account.
- The 760px message reading-width cap was a silent no-op: `Expanded` hands tight constraints, so the `ConstrainedBox` never bit and body text ran the full pane on any monitor. An `Align` loosens it now.
- The day divider, unread divider and channel-start header used a hardcoded 20dp gutter, sitting 10dp right of every message on phones; they follow the layout class now.
- The pin pill was the one header control without a 44dp hit area; the invite onboarding card used the create icon for a redeem action; the "System never picks true black" caption moved into the theme picker where the option it explains is visible; the invites "Uses allowed" field got an accessible name; the five admin rows got one-line descriptions; the sign-in Server field names the Space it is.
- Desktop settings cold-open read as loose text on a blank window (hairline border on a same-colour ground): the panel now sits on a sunken backdrop, with the float shadow reserved for when it genuinely floats over the app.

Recorded, not fixed here: the shared empty-state component extraction across the four admin lists, `AppSegmentedControl.inline`'s fixed-height text-scale risk (and its missing golden coverage), the four `ListTile` settings sections that bypass `AppListRow`'s focus ring, and the landscape channel-start clip under the app bar.

## Round three: the owner's design agent reviewed the screenshot pack (same day)

An external design review over the full 76-shot pack came back with a token-compliance list (its A1-A10), one bug claim, and a gap list.
Verified before acting, which mattered: five of its claims were artifacts.
The accent has not drifted (tokens are exactly the glacier anchors; the review measured anti-aliased pixels), the dark base is exactly `#17191C`, no 700 weight exists anywhere (the ramp stops at 600 and no bolder face is even loadable), the reaction "tofu" is the known snapshot-harness emoji gap (the live e2e capture shows the colour glyph), and the "missing" fingerprint step is built and wired into onboarding - cold renders just never walk the connect flow.

What was real, and fixed:
- `buildTheme` set almost nothing, so every raw Material widget ran M3 defaults: stadium-pill buttons, underline text fields, Material's own type ramp. The theme now carries the system - control-radius button shapes with 600-weight labels on all four button types, the hairline boxed input `AppInput` draws, an AppBar title from the scale, and a `TextTheme` mapped from `AppText`. Two traps found on the way: a button theme's `textStyle` replaces the inherited style wholesale (buttons silently fell back to the platform face until the family was named), and the global input theme double-boxed every field whose component draws its own chrome, so `AppInput`, the composer and the edit field explicitly opt out.
- The leave-call control was a filled red tile; danger is outlined, never filled.
- The wordmark now renders to spec (mono, medium, +0.04em) on both entry screens.
- Icons moved to the 1.5-stroke Lucide variants (the `Lucide300` variable-font cut; the snapshot harness loads that face too).
- The day divider and timestamps render in mono with tabular figures, per the type spec.
- Channel-row kebabs reveal on hover or focus with a pointer (semantics stay present while invisible - the first attempt dropped them and a test caught it); touch keeps them visible.

Its gap list, corrected: the fingerprint step, DM conversation view, message context menu, search, pins sheet and polls all exist - the captures simply cannot reach interaction states.
Genuinely still open from it: member profile popover, per-participant volume, timeout/kick moderation actions on member rows, edit history, saved items, low-bandwidth mode.
One reconcile note for the owner: custom emoji is built here while that reviewer's plan doc has it declined; their doc should be updated rather than the feature questioned.

## Round four: the motion and feedback spec (same day)

The design agent followed the reviews with a motion spec (11 live patterns in the claude design project), implemented the same day: spec curves (`easeOutCubic` in, `easeIn` out) and the .98 press ceiling, the selection marker growing from centre on its own clock beside the 100ms hover fill, reaction-chip and unread-dot confirmation pops, the member pane sliding from its edge (unmounting when hidden - it fetches while built), the compact drill-down with 30% parallax, the 280/180 modal, the connection banner pushing by animated height, hold-progress tint on message long-press, and theme switching joining the never-animates list.
Two contracts the tests defended during this: row height never animates (density is layout, not motion), and the hidden member pane must genuinely unmount.
One deviation and one deferral, both recorded: the hold tint runs over Flutter's own long-press timeout because `GestureDetector` is what publishes `SemanticsAction.longPress`, and the level-driven speaking ring (spec 09) needs a live audio-level stream beside the roster, whose churn-coalescing exists precisely to avoid per-level rebuilds.

## Round five: the error grammar, and a component-usage audit (same day)

The design agent's Error States spec landed alongside a three-specialist audit of how the app actually uses its own component library.
The two converged on the same finding from opposite directions, which is why they shipped together.

**The convergence: 27 failures were told only by a vanishing toast.**
The spec's rule is that a failure is a state, not an event - it appears at the point of the action, persists, and always ships a verb.
The audit counted 27 `showSnackBar` sites carrying the only record of a failed account deletion, block, report, role assignment, invite revocation, emoji upload and more, and found the design system had no persistent inline-error component to use instead (`AppCallout` deliberately has no danger tone).
`AppErrorState` closes that gap: outlined danger hairline, plain-language message, an optional mono detail line for whoever runs the server, and Retry/Dismiss verbs.
Account deletion - the most consequential of them, and the one whose own doc comment warned about exactly this - uses it now.

**Two different reds meant "danger".**
`ColorScheme.fromSeed` derives its own `error` from the accent seed, which is not the hand-picked `dangerText`; ten sites read Material's and fifteen read the token, with no rule.
`buildTheme` now overrides `error` with the token, so any raw `colorScheme.error` is correct by construction, and the ten sites were converted anyway.
The shared confirm dialog was also *filling* a button with it, which the grammar forbids outright; it and the account-deletion dialog now use `AppButton(variant: danger)`.

**Message lifecycle (spec 01).**
Sent, sending and failed are one `MessageTimeMark`: the timestamp, a clock plus "sending", or "not sent" in red.
Pending dims; **failed does not** - a failed message is still the author's to act on - and the row carries a red hairline down its left edge with Retry / Edit / Discard beneath.
Edit puts the text back in the composer and drops the failed row, so nothing written is ever lost.

**Offline is amber, and never blocks (spec 02).**
The banner keeps its warn tone and retry glyph and the composer stays open; the spec's queued *count* was built and then reverted, which is worth recording.
A live drift stream in the rail footer keeps every test that renders the rail from ever settling (the timer trap this file's own local-development notes describe), so the count needs a non-streaming read - a value refreshed on sync-status change - rather than a `watchSingle` behind an autoDispose provider.
Caught by the suite, not in review: three tests hung for five minutes each.

**Sign-in errors land on their field (spec 03).**
Wrong password marks the password field, a taken username marks the username, an unreachable host marks the server address with "Nothing was sent"; only errors no field owns fall back to the form.
The theme grew `errorBorder`/`errorStyle` so this is the default for every field in the app, not one screen's special case.

One spec item is deliberately **not** implemented: 05 asks to distinguish an expired invite (with its date) from an invalid one.
The server answers expired, spent, revoked and never-issued identically so codes cannot be mined, and naming the reason client-side would undo that from the other end.
The safe half - a local format hint for a typo, which contacts no server - is the only part worth taking.

`AppAsyncView` closes the first of those: one treatment for the three states every fetched surface has, with the error branch going through `AppErrorState` so a failed fetch obeys the same grammar as a failed action.
It keeps "nothing yet" separate from "here is the list" on purpose, since collapsing those is how the roles screen ended up rendering a blank page.
The two admin screens whose `_Message` widget was byte-identical use it now and gained a Retry they never had; the remaining sites are a mechanical follow-on.
It takes a plain `AppAsyncState` rather than an `AsyncValue`, so the design system stays free of a Riverpod dependency.

Recorded from the audit, not yet done: a `SettingsScreenScaffold` for eight verbatim-duplicated screen skeletons, a `runGuarded` helper for 26 near-identical catch blocks, `BackToButton` (done: the identical five-line `IconButton` around `closeScreen` in eight screens is one widget now, so a change to the back affordance is one edit and no screen can drift into a different glyph or a missing tooltip), the sign-in and onboarding fields moving onto `AppInput` (needs `helperText`/`autofillHints` passthrough first), 25 raw `ListTile`s that want `AppListRow`, nine invented `fontSize: 13` sites, and the multi-line `//` runs, which got the gate rather than the sweep: `scripts/check-comment-cap.sh` counts runs per file, `scripts/comment-cap-allow.txt` records each file's count at listing time, and the check fails when a file gains one.
Ratcheting rather than a big-bang sweep because 801 runs across 309 files predate the rule (broader than the audit's 174/68, which counted Dart only), and a sweep that large is unreviewable; lowering a number as a file gets fixed is.
Mutation-tested both ways: a new run in an unlisted file exits 1, the clean tree exits 0.
