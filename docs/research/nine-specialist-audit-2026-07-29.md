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
