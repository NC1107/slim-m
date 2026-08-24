<!-- SPDX-License-Identifier: Apache-2.0 -->
# Technical debt

From the 2026-08-14 multi-agent audit against `main` at be13b2f8.
Every item was confirmed by reading the code path at HEAD, not by reasoning from a comment or a doc.
Struck through when fixed, with the commit that closed it.

The full-stack review of 2026-08-11 lives in `REVIEW-2026-08-11.md`, and the accepted UI-feel and motion review lives in `ui-review.md`.
Neither is duplicated here.
The 2026-07-29 audit was closed in b4eab36 (#118) and its section has been removed; its one open item, the desaturated-presence golden that never runs, is carried forward here as TEST1, which supersedes it.

## Method

Fourteen passes: code quality, security, performance (server), performance (client and media), test quality, architecture, database, API contract, frontend lifecycle, backend domain logic, CI and release, a Discord-moderator product review, a Flutter engineering review, and a UX and UI review across mobile and desktop.

Evidence standards applied to every pass: verify at HEAD, quote real lines at real line numbers, no quote means no finding.
The database items were additionally confirmed with `EXPLAIN QUERY PLAN` against a throwaway database built by applying all 46 migrations.
The UX items were taken from 302 PNGs rendered from the real widget tree by `scripts/ui-snapshots.sh`.

The security and frontend-lifecycle passes returned no findings.

## Summary

70 items as found: 10 high, 43 medium, 17 low.
53 of them are now accounted for - 51 fixed, and MOD5 plus UX7 decided rather than built - leaving 17 of the original 70 open, none of them high: CP2 was the last, and was downgraded to Medium on 2026-08-16 when its own numbers refused its recorded fix.
MOD1's own work opened three follow-ups (MOD10 to MOD12), of which MOD11 is already closed by the same decision that closed MOD5. MOD2's opened one, MOD13.

Closed on 2026-08-14, in order: DB1 to DB4 in #663, TEST3 to TEST10 in #667, and CP3, CI1 and CI2 in #668.
CP1 is partly fixed in #668 and stays open, downgraded to Medium.
MOD3 closed on 2026-08-15 in #670, MOD1 in #675, and MOD2 in #681. MOD5 and MOD11 were decided rather than built, in #677; see decision 0016.

The server performance and correctness items closed on 2026-08-19: SRV4 in #711, SRV3 in #715, SRV2 in #719, and SRV5 in #721.

A second 2026-08-19 batch closed API3 (#725), API2 (#726), MOD9 (#727), ARCH1 (#728), SRV1 (#729), MOD12 (#731), UX3 (#733), CS1 (#734), CP8 (#735), MOD6 (#736), TEST2 (#737) and UX2 (#738), plus the server foundations of MOD4 and MOD7 (#732) with their client screens backlogged. UX7 was decided rather than built (disabled text is WCAG-exempt). CP7, MOD8 and the two new retention findings CS4/CS5 (#730) were backlogged, and a profile-mode memory pass that day confirmed the client's resting footprint is healthy, so the retention work waits for real message volume.

A client-performance pass on 2026-08-23/24 profiled the CP cluster and closed CP4 (#742), CP6 (#743) and CP5 (#744). CP2 was measured for the first time and stays backlogged - its paint cost is a fraction of a millisecond even at 2000 visible objects. CP1 was reviewed and deliberately left open: the profile rated it modest allocation churn during a gesture, while its safe fix carries the exact risk this file already warns about (a stale-cache miss freezing the presence tiles). The pass also surfaced CP9, the same re-shape-every-paint waste CP5 fixed but in sticky-note labels; CP9 was then built and closed (#746). Two test-coverage gaps were closed alongside it: the emoji HTTP routes (#740) and the reports queue controller (#741). The data layer's catch-up write path CD1 was batched next (#747).

Nine findings from the same day's CI audit closed in #665, and are not itemised here because that audit was reported separately: the client path filter that matched every push, the red-streak watchdog failing its own job, `secrets: inherit` on the copr job, the deployed image carrying no sbom or provenance, the apt list duplicated across three workflows, two SPDX headers labelling client tooling AGPL, the SPDX gate passing on an empty file list, three stale concurrency keys, and unpinned base images.

Worth reading before picking anything here: of the fourteen items worked on since this audit was written, seven had a recorded fix that was wrong - TEST3 understated the damage, TEST6 and TEST7 each proposed a fix that would have broken the test, CP3's would have shipped a resubscribe bug, CP1's would have frozen the presence tiles during a pan, MOD3's would have let a re-removed member sign straight back in, and CP2's named a cost its own measurements put at 12us a frame.
Each is documented in place rather than deleted.
Treat a "Fix:" line here as a starting hypothesis to verify, not an instruction.

By area: test quality 15, moderation 9, client performance 8, UX and UI 7, server performance and domain 6, client architecture 6, database 4, API contract 3, client state 3, client data layer 3, client code quality 2, CI 2, architecture 1, platform 1.

Four reported findings did not survive verification and were corrected or rejected; they are recorded at the end so nobody re-finds them.

## Server: database and data access

- ~~**DB1. `DELETE FROM reactions WHERE user_id = ?` has no supporting index**~~ (`store/account_deletion.rs:176`). High. Fixed in 921e97ef (#663).
  `reactions` is `PRIMARY KEY (message_id, user_id, emoji) WITHOUT ROWID`, so a `user_id` predicate cannot use it and the statement plans as `SCAN reactions`, inside the single transaction that holds the deployment's one write lock.
  `reactions` grows with all content, so the cost only rises; this is the bug class migration 0019 fixed elsewhere and missed here.
  Fix: new migration, `CREATE INDEX reactions_user ON reactions(user_id);`. Effort: small.

- ~~**DB2. `DELETE FROM attachment_uploaders WHERE uploaded_by = ?` has no supporting index**~~ (`store/account_deletion.rs:189`). Medium. Fixed in 921e97ef (#663).
  The table leads with `sha256`, so a bare `uploaded_by` predicate plans as `SCAN`, in the same exclusive transaction as DB1.
  Fix: new migration, `CREATE INDEX attachment_uploaders_uploaded_by ON attachment_uploaders(uploaded_by);`. Effort: small.

- ~~**DB3. `members_with_role` full-scans `member_roles`**~~ (`store/roles.rs:106`). Medium. Fixed in 921e97ef (#663).
  `WHERE role_id = ?` cannot use the `(user_id, role_id)` primary key, and its caller `previously_visible_to` (`http/overwrites.rs:228`) runs on every create, update and delete of a role-scoped channel overwrite.
  Fix: new migration, `CREATE INDEX member_roles_role ON member_roles(role_id);`, which yields a covering index. Effort: small.

- ~~**DB4. `DELETE FROM channel_overwrites WHERE target_type = 'member' AND target_id = ?` has no supporting index**~~ (`store/account_deletion.rs:196`). Low. Fixed in 921e97ef (#663).
  The table leads with `channel_id`. Bounded by channels times overwrite entries rather than by content volume, so lower than DB1 and DB2, but in the same exclusive transaction.
  Fix: `CREATE INDEX channel_overwrites_target ON channel_overwrites(target_type, target_id);`, shippable in the same new migration as DB1 to DB3. Effort: small.

## Server: performance and domain logic

- ~~**SRV1. The reaction summary is recomputed once per connected client**~~ (`http/ws/authorization.rs:314`). Medium. Fixed in #729.

- ~~**SRV2. The retention sweep holds the write lock across roughly 1000 sequential round trips**~~ (`store/message_retention.rs:129`). Medium. Fixed in #719.

- ~~**SRV3. `list_dm_conversations` costs 1 + 2N round trips**~~ (`store/dms.rs:234`). Medium. Fixed in #715.

- ~~**SRV4. Attachment serving buffers whole files and supports no Range requests**~~ (`media/mod.rs:196`). Medium. Fixed in #711.

- ~~**SRV5. A retried invite redemption either falsely fails or burns a second use**~~ (`store/invites.rs:286`). Medium. Fixed in #721.

- ~~**SRV6. The stale-call sweep evicts participants one at a time**~~ (`lib.rs:228`). Low. Fixed in #761.
  `sweep_stale_voice_calls_at` now publishes `VoiceActivityChanged` for every stale pair up front, then fans the removals out with `for_each_concurrent` bounded by `STALE_SWEEP_CONCURRENCY` (16), so a blip that expires many heartbeats in one tick no longer serialises N LiveKit round trips. Each removal still swallows its own error per pair, so one failure cannot cancel the rest, and the 10s ticker still awaits the sweep before the next tick. Two tests pin it: a burst overlaps (mutation-checked against concurrency 1) and the fan-out stays under its ceiling (mutation-checked against an unbounded bound).

## Server: API contract

- **API1. The `Class::Read` rate-limit class does not mean what three call sites assume.** Medium.
  `Class::Read` is documented for unauthenticated metadata reads (`/version` and its capability list) and carries a *tighter* budget than `Class::Write`: `(20 burst, 2/s)` against `(30, 5)`.
  57 authenticated routes charge `Class::Write` regardless of whether they read or write, making `Write` the de-facto authenticated class; the outliers are `http/metrics.rs:55` and `http/analytics.rs:128,180`, which charge an authenticated admin read against the unauthenticated class.
  The live consequence is on `voice::roster` (`http/voice.rs:260`), whose own doc comment tells clients to poll it on an interval while it shares the `Write` bucket with token mint, heartbeat and kick.
  Moving it to `Class::Read` would tighten it, not loosen it, so this is a decision rather than a swap: either widen `Read` to mean "cheap authenticated read" and move the read-only GETs onto it (`voice::roster`, `http/space.rs:43`, `http/members.rs:242`), or give polled reads their own class and move `metrics` and `analytics` back onto `Write`. Effort: medium.

- ~~**API2. Channel, category and role creation are not idempotent**~~ (`http/channels.rs:190` and siblings). Medium. Fixed in #726.

- ~~**API3. 62 of 113 documented operations omit the 429 response**~~ (`schema/openapi.yaml`). Medium. Fixed in #725, with a gate so it cannot drift back.

## Architecture

- ~~**ARCH1. The attachment wire shape is defined three times**~~ (`http/gifs.rs:298`, `http/attachments.rs:51`). Low. Fixed in #728.


## Client: package boundaries and architecture

- **CA1. `data`'s public barrel leaks drift's generated row classes** (`client/packages/data/lib/data.dart:12`). Medium.
  It exports `Channel`, `Message` and `ChannelCategoryRow`, which implement drift's `Insertable<T>`/`DataClass`, so most of `app` is transitively coupled to drift's interfaces without importing drift.
  This is the coupling that makes the local-store swap, or the Postgres move CLAUDE.md anticipates, expensive.
  Fix: give `data` plain DTOs that repositories map drift rows into at the boundary, so generated types never leave `lib/src/`. Effort: large.

- ~~**CA2. A widget imports drift directly and bypasses the store API**~~ (`client/packages/app/lib/src/widgets/channel_rail.dart:8`). Medium. Fixed in #752.
  The widget no longer imports `package:drift/drift.dart`; the drift `Value` wrap a nullable `categoryId` needs now lives behind a `Channel.repositioned({categoryId, position})` extension in the data layer, and the rail calls that. In practice this was not a store *write* the entry implied but the pure in-memory overlay `_withPendingOrder` builds to render a reorder before the server confirms it (the store is untouched until then), so the fix is the boundary extraction rather than a new store method. The existing reorder test still passes and a data-layer test pins the transform.

- **CA3. `rtc` reaches into `livekit_client`'s private `src/`** (`client/packages/rtc/lib/src/broadcast_bridge.dart:26`). Medium.
  An `// ignore: implementation_imports` pulls in `src/managers/broadcast_manager.dart`, inside the one package whose own doc says it exists to contain the livekit dependency.
  `src/` carries no semver contract, and this project has already moved livekit_client once, so a point release can silently break iOS screen sharing.
  Fix: pin livekit_client exactly and add a targeted test against the internal API's shape so a change fails loudly rather than silently. Effort: medium.

- **CA4. Firebase is initialised in two places** (`client/packages/app/lib/main.dart:125`). Low.
  `main.dart` calls `Firebase.initializeApp()` directly, duplicating the guarded call in `platform/lib/src/fcm_token_channel.dart:47`, in the package whose doc says it exists to keep the app off platform-specific mechanisms.
  Fix: move it behind the same `platform` seam so there is one initialisation call site. Effort: small.

- **CA5. The canvas sync engine lives as widget State** (`client/packages/app/lib/src/screens/canvas/canvas_pane.dart:78`). Medium.
  `_CanvasPaneState` owns the document model, cursor relay, remote stroke drafts, media-slot sync and activity log as plain fields rather than behind a provider, unlike `SyncController`'s message and channel sync.
  It cannot be unit-tested without mounting the widget tree, and no other screen can subscribe to it.
  Fix: move it behind a `StateNotifierProvider.family` keyed on channel id, leaving `CanvasPane` a thin consumer. Effort: large.

- **CA6. The analyzer runs at `flutter_lints` defaults** (`client/analysis_options.yaml:20`). Low.
  Both the workspace root and `packages/app` have an empty `linter: rules:` block and no strict analyzer flags.
  This matters more than usual here because the wire format is hand-parsed JSON rather than generated from `schema/openapi.yaml`, so `strict-casts` and `strict-inference` are the analyzer's only leverage over that boundary.
  Fix: enable `strict-casts`, `strict-inference` and `strict-raw-types` at the workspace root, plus `unawaited_futures` given how much of this codebase relies on deliberate fire-and-forget. Effort: medium.

## Client: state management

- ~~**CS1. The whole presence map is watched with no `.select`**~~ (`client/packages/app/lib/src/providers/presence_controller.dart:22`). Medium. Fixed in #734.

- **CS2. `VoiceState` bundles a high-churn participant list with low-churn flags** (`client/packages/app/lib/src/providers/voice_state.dart:33`). Medium.
  `participants` updates on every join, leave, mute and speaking change while sharing one state object with `cameraEnabled`, `deafened` and `error`, and a workspace-wide search finds zero `voiceControllerProvider.select` call sites across roughly ten consuming widgets.
  Fix: split `participants` out, or add `.select`-based derived providers for the flags each widget actually reads. Effort: medium.
  The single highest-impact consumer, `HomeShell.build` (the whole compact shell rebuilt on every room event, to read only `state` and `channelId`), was scoped with a `(state, channelId)` record `.select` in #817, pinned by `home_shell_voice_watch_scope_test`. An audit of the other watchers changes the shape of what remains: most legitimately consume `participants` (`channel_rail_channel_rows`, `voice_strip_indicator`, `member_profile`, `canvas_pane_gestures`, `fullscreen_video_overlay`, `voice_settings_screen`) or a wide flag slice threaded whole into a helper (`channel_rail_frame` and `collapsed_rail_strip` both hand the state to `railVoiceToggleButtons`), and `voice_screen` reads nearly all of it. So the `.select`-per-widget half is largely done where it cleanly applies; the remaining win is the structural one - splitting `participants` into its own provider so the flag-and-helper consumers stop churning without each needing a fragile multi-field select.

- ~~**CS3. The same `watchChannels()` StreamBuilder is reimplemented in six widgets**~~ (`client/packages/app/lib/src/screens/dm_call_button.dart:27`). Medium. Fixed in #749.
  A `channelByIdProvider(String id)` family (`providers/channel_by_id_provider.dart`) now watches a single indexed row via the store's existing `watchChannelRow`, so a widget rebuilds only when its own channel changes rather than on every write to any channel, and riverpod folds identical ids into one shared subscription. Only four of the six listed sites were genuine per-id filters and were routed through it - `dm_call_button`, `rail_call_summary`, `voice_strip_indicator`'s `CallChannelName`, and `compact_channel_app_bar`; each keeps its own absent-channel fallback (hide, "a call", "In a call", or a blank-but-visible bar). The other two named sites turned out to consume the whole list, not one id: `command_palette` searches across all channels, and `channel_rail` renders the full deduped rail (CP8's `watchRailChannels`), so both were correctly left alone.

- **CS4. `MessageExtrasController`'s map grows unbounded for the session** (`client/packages/app/lib/src/providers/message_extras.dart:99`). Medium.
  `StateNotifier<Map<String, MessageExtras>>` keyed on message id, one entry per distinct message ever seen (live, every paged page, search, pins), each holding a reactions list, an attachments list and a poll. Nothing evicts one entry at a time (`:26`) and the provider is not `autoDispose`; only sign-out `clear()`s it. The subscription is cancelled on dispose, so this is retention, not a leak.
  Surfaced by the 2026-08-19 memory profile: the resting footprint is healthy, so this only matters once a session pages thousands of messages. Backlogged until message volume proves it, per owner. Shares a root with CD2; a per-channel retention sweep should evict extras alongside the store rows.
  Fix: LRU-cap the map by message id, evicting only entries no longer visible, or fold into the CD2 sweep. Effort: medium.

- **CS5. `BatchProfilesController`'s map is screen-lifetime and uncapped** (`client/packages/app/lib/src/providers/user_profiles.dart:48`). Low.
  `StateNotifier<Map<String, UserProfile?>>`; one entry per distinct author/reporter resolved, removed only on a `ProfileChanged` eviction or sign-out `clear()`; not `autoDispose`. The sibling single-id `userProfileProvider` is `autoDispose.family` and fine; only the batch map accumulates.
  Entry size is display-name-sized, so impact is small; recorded from the 2026-08-19 memory profile as a known-bounded-in-practice item, backlogged until it proves an issue.
  Fix: LRU-cap, or accept given the tiny per-entry size. Effort: small.

## Client: performance

- **CP1. Canvas presence tiles rebuild on every pan and zoom frame.** Medium, was High. Partly fixed in #668.
  The recorded fix must not be applied as written, and that is the useful half of this entry. It proposed keeping camera-only changes away from the presence layer, via a separate notifier or a `ValueNotifier<Camera>`. The layer reads `document.camera` and hands it to every tile, and `document.worldView` to its own visibility pass (`canvas_presence_layer.dart:236,246`), so a camera change it does not see is tiles frozen in place while the canvas pans under them.
  What was actually wrong is narrower and is fixed: `setCamera` notified unconditionally, including when `_clamp` returned the camera already held, which is what a gesture run into a world edge or a zoom stop does for as long as the finger stays down. Measured before the fix, twenty pointer events held against an edge produced twenty notifications and twenty full presence rebuilds of an unchanged frame. `setViewport` immediately above it had always had that guard.
  What remains, and why this stays open at Medium: on a camera that really did move, the layer still re-derives tile keys, the identity map and the on-canvas rects, none of which depend on the camera at all - only `_visibility.update` and the tile transforms do. Splitting the camera-independent prefix from the camera-dependent suffix is the real fix and is untouched here. Effort: medium.
  Reviewed 2026-08-24 in the CP-cluster pass and deliberately left open. The profile rated it modest - small-N allocation and sort churn during a pan or pinch, not dropped frames - while the safe fix needs a version counter threaded through every `CanvasPresenceTileOverrides` mutation plus a signature cache whose one missed invalidation is a frozen or mispositioned tile, the exact wrong-fix shape this entry already warns against. Low value against real risk; do it only if a large roster makes the gesture-time allocation actually show up in a profile.

- **CP2. Dragging one canvas object repaints the whole scene** (`client/packages/voice_canvas/lib/src/canvas_document.dart:236`). Downgraded to Medium on 2026-08-16. Model half fixed in #687; the repaint half is untouched and is the part the title names.
  The recorded fix pointed at the wrong layer, and the measurements are the useful half of this entry. It said the per-move `Float32List` copy and the grid reindex were the cost. They are not: timed against a 2000-object document in a debug JIT build, `moveObject` ran 3.8us per call and `refresh()` 8.7us, about 12us for a whole pointer event against a 16ms frame. Removing the allocations moved the wall clock by roughly 7%, inside the noise. Whatever makes a drag expensive is in the paint, which none of that touches.
  What *was* wrong, and is fixed, is a leak the entry never mentions. `moveObject` freed its grid slot and inserted a fresh one, and `UniformGrid` never renumbers or reuses a parked slot, so every pointer event leaked one for the session - a few hundred per drag, each still walked by every later linear cull, with `_strokes` growing a null beside it. 200 moves took the slot count from 1 to 201; it now stays at 1. `UniformGrid.move` keeps the slot, the points are shifted in place, and the object keeps its identity, so a pointer event allocates one `Path` rather than a `Path`, a `Float32List` and a `CanvasStroke`.
  Remaining fix, and it is the one the title describes: the dragged object still lives in the document, so `refresh()` notifies and `StrokePainter` repaints the whole culled set at pointer rate. Isolating it needs the ephemeral-layer treatment `DraftStroke` already has ("its own layer and its own listenable so pointer-rate repaints never touch the committed ink"), which means teaching `StrokePainter` to skip one slot and drawing it above. Not attempted here because the benefit is still unmeasured: the paint cost was never timed, and this entry has already prescribed one fix that the numbers refused. Measure the paint first. Effort: medium, once measured.
  Measured 2026-08-24 in the CP-cluster pass, against the real `StrokePainter.paint`/`GridPainter.paint` over a 60-event drag: the paint scales ~0.35us per visible object in a debug JIT build, so a full-layer repaint on drag costs a fraction of a millisecond even at 2000 visible objects and only single-digit percent of a frame at an unrealistic density. The grid layer is flat regardless. Confirmed negligible and stays backlogged; revisit only if a genuinely dense shared canvas proves otherwise, and only then with the ephemeral-layer fix above.

- ~~**CP3. Per-participant platform-channel calls fire on every room event**~~ (`client/packages/rtc/lib/src/local_audio.dart:65`). High. Fixed in #668.
  Confirmed as recorded, and the cost is real rather than a local field write: flutter_webrtc's `enabled` setter invokes `mediaStreamTrackSetEnable` with no equality check of its own, and for an audio track it also fires that track's `onMute`/`onUnMute`.
  The recorded fix was keyed wrongly and would have shipped a bug, which is worth keeping written down. It said to cache per track *id*. A resubscribe reuses the publication and its sid, so an id-keyed cache reads as a hit and skips the reapplication that exists precisely to catch a track that came back at source-default volume - the invariant the file's own header documents. The shipped cache is keyed on the platform track object, which a resubscribe replaces (`addSubscribedMediaTrack` builds a new `RemoteAudioTrack` around a new `MediaStreamTrack`), so it correctly misses. Mutation-testing the id-keyed version fails the resubscribe test.

- ~~**CP4. Every camera tile rebuilds on every room event**~~ (`client/packages/rtc/lib/src/camera_view.dart:60`). Medium. Fixed in #742.
  A shared pure predicate `trackEventAffectsIdentity` now passes only the events that can change a participant's video - track publish/unpublish, subscribe/unsubscribe, mute/unmute, and that participant joining or leaving - and both `CameraView` and `ScreenShareView` gate their `setState` on it. An adversarial review traced every excluded LiveKit event to a handled one co-fired at the same site, so no camera can go silently stale.

- ~~**CP5. Cursor labels re-shape text on every paint**~~ (`client/packages/voice_canvas/lib/src/canvas_live_painters.dart:268`). Medium. Fixed in #744.
  A per-cursor `CursorLabelCache` keeps the laid-out `TextPainter`, rebuilding it only when the label or its colour changes, pruned each frame for absent cursors and disposed on teardown. The drawn chip is byte-identical for an unchanged cursor; a test asserts the laid-out text, not just the layout count.

- ~~**CP6. `splitStroke` is O(L squared) per completed stroke**~~ (`client/packages/voice_canvas/lib/src/stroke_splitter.dart:54`). Medium. Fixed in #743.
  Both budgets are tracked incrementally now: the bounding box is a running min/max, and the encoded length a running sum of each coordinate's JSON length, recomputed only when a new point moves the segment origin. Measured 5-11x faster on realistic strokes. The output must be byte-for-byte identical (an over-budget segment is a 400 and vanishing ink), so an equivalence test pins it against a verbatim copy of the old function over ~2000 random strokes.

- **CP7. The transcript's live-watched window grows without bound** (`client/packages/app/lib/src/providers/channel_history.dart:153`). Medium.
  `loadOlder()` grows `state.window` by up to 50 per scroll-back with no ceiling, and `channel_screen.dart:345` passes it straight through as the `limit` of a drift `.watch()` query that re-runs on any write to the messages table anywhere in the app.
  Fix: cap window growth, or stop re-deriving the whole window from one growing-LIMIT stream. Effort: medium.
  Backlogged 2026-08-19 per owner: the memory profile that day confirmed it is not yet an issue (884 KB local cache); it shares a root with CD2/CS4, best done as one retention sweep when volume warrants.

- ~~**CP8. Every incoming message rebuilds the entire channel rail**~~ (`client/packages/app/lib/src/widgets/channel_rail.dart:151`). Medium. Fixed in #735.

- ~~**CP9. Sticky-note labels re-shape text on every paint**~~ (`client/packages/voice_canvas/lib/src/canvas_painters_shapes.dart:51`). Medium. Fixed in #746.
  A `NoteLabelCache` (its own file, like `CursorLabelCache`) now keeps each note's laid-out `TextPainter`, keyed on a `(text, zoom, w, h)` record - everything the layout depends on - so a pan reuses it while a zoom, a resize or an edit rebuilds it. Reconciled to the visible notes each frame and disposed on teardown; a miss only ever re-lays-out, never draws stale.

## Client: data layer

- ~~**CD1. Catch-up writes are unbatched**~~ (`client/packages/data/lib/src/message_store.dart:306`). Medium. Fixed in #747.
  `applyMessages` now reads every colliding row in one select, resolves the winning version per id in memory, writes the survivors in one `db.batch()`, and advances each channel's cursor once - the four-plus round trips a message are gone. The body moved to `message_store_batch.dart` to keep the file under budget. It must decide idempotency and ordering exactly as `applyMessage` does, so an equivalence test runs the same mixed batch through both paths and diffs the result; an adversarial review caught an equal-seq tie-break (first-wins vs the sequential path's last-wins) before merge, now fixed and pinned.

- **CD2. The local store has no retention policy** (`client/packages/data/lib/src/message_store.dart:27`). Medium.
  Every delete path fires only on a server-signalled reset, a delete, or sign-out; nothing evicts by age or count, so the local sqlite or OPFS store grows for the life of an account as history pagination pages older messages in.
  Fix: cap cached rows per channel, or evict channels not opened recently, the way the avatar and attachment byte caches already bound themselves. Effort: large.

- ~~**CD3. The seq-adjacency rule is implemented twice**~~ (`client/packages/app/lib/src/providers/message_ops_sync.dart:84`). Low. Fixed in #753.
  `liveOpDecision` and `LiveOpOutcome` moved to a neutral `op_adjacency.dart`; `CanvasSync.applyLive` now switches on `liveOpDecision(seq, cursor)` instead of reimplementing the three comparisons, so a future change to the gap-detection rule lands in one place. Behaviour is preserved: the canvas convergence property tests (out-of-order delivery, the exact gap path) and `liveOpDecision`'s own unit tests both stay green.

## Client: code quality and platform

- ~~**CQ1. Channel extras are hydrated on mount but not on channel switch**~~ (`client/packages/app/lib/src/screens/channel_screen.dart:125`). Medium. Fixed in #750.
  `ChannelScreen.didUpdateWidget` now calls `_hydrateExtras()` again when the channel id changes, and `ThreadScreen` gained a matching `didUpdateWidget` that re-runs `_ensureThreadChannelRow`, so the thread modal (which reuses its State across a switch) seeds the new channel's reactions, polls and attachments instead of leaving them blank until a live event. The regression test isolates the hydration fetch from channel_history's paging by the absence of a `before` cursor, and is mutation-checked against dropping the re-hydrate call.

- ~~**CQ2. `home_shell.dart:429` reinvents `firstOrNull`.**~~ Low. Fixed in #758.
  `_ChannelTitle.build` now uses `.firstOrNull` (dropping the `.cast<Channel?>().firstWhere((c) => true, orElse: () => null)`), matching `ConversationPane.build`'s own lookup in the same file. Provably equivalent; the home-shell suite stays green.

- ~~**CQ3. Extras merge can never reflect a reaction dropping to zero**~~ (`client/packages/app/lib/src/providers/message_extras.dart:169`). Low. Fixed in #759.
  The authority question the entry named was settled by reading the server: `list`'s enrichment (`http/message_enrich.rs::with_reactions`) carries every message's reactions, attachments, poll and thread in full and per-viewer, so a REST fetch is authoritative and an empty reaction list from it means the reactions are genuinely gone. `applyMessages` now passes `authoritative: true`, which lets an empty reaction list win and clear the stale tally; the live `applyMessage` path still coalesces because its frame omits reactions. Only reactions replace: the nullable fields (poll, thread) still coalesce, because they only ever gain information and a blanket replace let a slower REST page that predated a live `ThreadUpdated` null a freshly-opened thread's affordance back out - a regression caught in review before merge. `message_extras_authority_test.dart` pins both directions plus that thread guard, mutation-checked.

- ~~**PLAT1. Platform channel calls are unguarded, including one on the FCM background isolate**~~ (`client/packages/platform/lib/src/call_notifications.dart:41`). Medium. Fixed in #751.
  `showIncomingCall` now wraps its `invokeMethod` in `try`/`catch` for `PlatformException` and `MissingPluginException`, matching the sibling channels, so a native failure on the FCM background isolate's top-level handler is a missed banner rather than an uncaught throw that drops the whole push. By the time this was reached the other three files the entry named (`call_lifecycle_channel`, three calls; `notification_tap_channel`, one) had already been guarded, so this closed the last unguarded call. Two tests assert both exception kinds are swallowed, mutation-checked against removing the guard.

## Moderation and community safety

Judged against real moderator scenarios rather than code style.
Found sound and not listed: the escalation guards, per-channel permission masking, voice ejection, canvas moderation via `MANAGE_CANVAS`, and the conditional UPDATE that stops two moderators both resolving one report.

- ~~**MOD1. There is no way to delete more than one message at a time**~~ (`http/messages.rs:225`). High. Fixed in #675.
  `POST /channels/{channelId}/messages/bulk-delete` takes up to 64 ids, scoped to `MANAGE_MESSAGES`, recorded in `moderation_audit_log` (which needed migration 0049 to widen its action set - 0048's CHECK had no room, exactly as decision 0015 warned a later bulk path would find).
  The by-author-and-time-window half of the recorded fix was deliberately not built: no index supports `(author, channel, since T)`, so it plans as a channel seek that then walks the channel's whole live history. No `SCAN`, so the existing plan gate would pass while the query stayed unbounded. It needs its own index and migration; carried as MOD10 below.
  One thing the entry did not anticipate, recorded because it is a real asymmetry rather than an oversight: the bulk path refuses a batch naming a message whose author holds a permission the caller does not, and the single delete has no such rule. `escalation_guard` has never guarded a message. So a moderator can still delete an administrator's message one at a time. Carried as MOD11.

- ~~**MOD2. A wave of new joiners cannot be found**~~ (`client/packages/app/lib/src/widgets/member_pane.dart:113`). High. Fixed in #681.
  The pane gains a search box matching username and display name, and a toggle that reorders it newest-account-first. Both are client-side over the roster the pane already holds, so neither costs a request, and the recorded fix was right that no server change was needed.
  Two details the entry did not specify, decided while building. The sort ties break on username, because several accounts registered in the same millisecond is exactly what a scripted wave looks like and a list that reshuffles between rebuilds cannot be worked through. And the header keeps counting the whole roster while a filter is applied: that number is what somebody reads to learn how big the Space is, and a search box quietly changing it would answer a question nobody asked.
  The multi-select half of the description is deliberately not built and is carried as MOD13; the search and sort halves are what the recorded fix asked for and what a moderator needs first.

- ~~**MOD3. Undoing a removal or a timeout erases who did it**~~ (`store/removals.rs:141`, `store/timeouts.rs:94`). High. Fixed in #670.
  Fixed by `moderation_audit_log` (migration 0048), an append-only table after `canvas_audit_log`'s shape, written in the same transaction as each act. `space_removals` and `member_timeouts` are untouched.
  The recorded fix was rejected, and this is the fifth entry whose prescribed fix would have shipped a bug, so it is worth the space. It said to soft-close with `lifted_at`/`lifted_by`. Three things make that unsafe, each verified against the source: `user_id` is the PRIMARY KEY on both tables, so history needs a surrogate key and a full SQLite table rebuild on each; both writers use `ON CONFLICT(user_id) DO UPDATE`, so re-removing a member would update the lifted row and leave it lifted, returning 204 while the member signs straight back in; and 15 statements read these tables rather than the six implied here, two of which fail closed in ways that are hard to undo on a self-hosted deployment - `sessions.rs:397` gates login, and `roles.rs:313` is the last-administrator guard. A third, `timeouts.rs:158`, is built with `QueryBuilder`, so it is absent from `.sqlx/` and invisible to a review that greps for query macros.
  It would also have reversed a decision written into a shipped, immutable migration: `0020_member_timeouts.sql:9` says "One row per member rather than a history".
  Reasoning and the accepted drift risk are in `docs/decisions/0015-moderation-audit-trail.md`.

- ~~**MOD4. Resolved reports have no read surface**~~ (`store/reports.rs:173`). Medium. Server foundation shipped in #732 (`GET /reports/history` merges resolved reports and the audit log); the moderator history SCREEN is backlogged, per owner.

- ~~**MOD5. A removed or timed-out member cannot say anything back**~~ (`store/sessions.rs:396`). High. Decided on 2026-08-15, not built.
  The entry asked the right question - "whether an in-product appeal path is wanted at all is a product decision, not a defect" - and the owner's answer is no. There will be no appeal route, no DM exemption for a timed-out member, and no read-only mode for a removed account.
  Reasoning and the consequences accepted with it are in `docs/decisions/0016-message-deletion-has-no-hierarchy.md`. The short of it: one deployment is one community, its moderators are reachable by whatever the group already uses, and an appeal inbox reachable by removed accounts is a surface a raid can use.
  A wrongly removed member still has recourse, just not self-service: an administrator can restore them, and since MOD3 that restoration is recorded with who did it. MOD6 - showing a timed-out member the reason - stays open and is worth more here than an appeal path would be.

- ~~**MOD6. A timeout's reason is captured but never shown to the person it was issued against**~~ (`http/users.rs:150`). Medium. Fixed in #736.

- ~~**MOD7. The report queue has no live sync**~~ (`hub/event.rs`). Medium. Server foundation shipped in #732 (a moderator-gated, field-free `ReportsChanged` event); the client queue consumer is backlogged, per owner.

- **MOD8. A reporter never learns anything happened** (`http/safety.rs:211`). Medium.
  `file_report` returns only the new id; there is no "my reports" route, no resolution notification, and `GET /reports` is gated on `MANAGE_MESSAGES`, so a reporter cannot look up even their own report.
  Fix: a narrow status-only "my reports" read, or a notification when a reporter's own report is resolved. Effort: small.
  Backlogged 2026-08-19 per owner, alongside the MOD4/MOD7 moderation client work: needs a reporter-facing notification surface.

- ~~**MOD9. Nothing links a returning account to a removed one**~~ (`migrations/0002_core_schema.sql:19`). Medium. Fixed in #727 (surfaced to moderators; SRV5 already recorded the invite).

- **MOD10. Bulk delete cannot select by author and time window** (`http/messages_bulk.rs`). Medium.
  The id-list form shipped; the raid case still wants "this author's last N minutes here" as one call rather than a client first selecting them.
  Blocked on an index: `messages_channel_live (channel_id, seq DESC)` and `messages_author (author_id)` exist, neither serves the pair, and a query using them alone is unbounded without reporting a `SCAN`. Needs a new index and therefore a new migration. Effort: medium.

- ~~**MOD11. Deleting one message has no containment rule, deleting several does**~~ (`http/messages.rs:255`). Medium. Resolved on 2026-08-15 by removing the guard.
  The entry offered two ways out - apply the guard to the single delete, or decide message deletion is exempt and record it. The owner chose the second, so the asymmetry is gone in the direction that leaves both paths alike: `MANAGE_MESSAGES` reaches every message in the channel, an administrator's included.
  `docs/decisions/0016-message-deletion-has-no-hierarchy.md` records why a guard on the bulk route alone protected nothing - it refused sixty-four at once while allowing the same sixty-four one at a time, a difference in patience rather than permission.

- ~~**MOD12. A delete publishes no unpin and no thread update**~~ (`http/messages.rs:265`). Medium. Fixed in #731.

- **MOD13. Nothing in the app can select several members, or several messages** (`client/packages/app/lib/src/widgets/member_pane.dart`). Medium. Message half fixed in #683; member half still open.
  MOD2 makes a wave of throwaway accounts findable and MOD1 gives the server a bulk delete taking 64 ids, but there is still no multi-select anywhere in the client, so acting on what the search now surfaces is one member and one message at a time.
  This is the reader for the endpoint #675 shipped without one, which is the shape `canvas_audit_log` also took and decision 0037 defends.
  The message half is built: a transcript enters selection from a message's own menu, rows become one target apiece, and a bar in the composer's slot deletes the lot in one request. `bulkDeleteMessages` is out of `app_reachability_test.dart`'s unreachable allowlist as a result, which is the mechanical confirmation that the endpoint now has a reader.
  The entry as first written conflated two jobs, and only one of them was ready. Selecting messages spends an endpoint that already exists; selecting *members* spends nothing, because there is no bulk remove, no bulk timeout and no bulk role grant on the server. Building a member multi-select first would have been a selection UI with no verb behind it.
  Remaining fix: a bulk membership route to act on, then selection in `member_pane` against it. That order, not the reverse. Effort: medium.

## UX and UI

Taken from 302 PNGs rendered from the real widget tree.
Deliberately excluded: everything in `ui-review.md` (accepted motion and feel work), and M8 in the 2026-08-11 review.

- ~~**UX1. Threads hide the parent channel on desktop**~~ (`thread-desktop-light.png`). Medium, desktop. Fixed in #824.
  An in-app thread open now sets `openThreadProvider` and the shell docks the thread as a fixed-width side pane beside the transcript at widths that fit it (`fitsThreadPane`), reusing the member pane's own reveal; the thread and the roster share that one third-pane slot so the transcript is never squeezed by two. The recorded fix's own words, with two deliberate limits: the `/thread/:id` modal route is kept unchanged for compact widths and cold deep links (so URLs and e2e keep working), and the docked pane is not URL-backed, so a reload closes it back to the channel. Docking a cold deep link too would need an async router redirect that reads layout and sets the provider - carried as a follow-up rather than built here.

- ~~**UX2. Collapsing the rail removes the only access to settings, mic and deafen**~~ (`rail-collapsed-desktop-light.png`). Medium, desktop. Fixed in #738.

- ~~**UX3. The mention pill and search operator chip miss AA contrast**~~ (`design_system/lib/src/components/forms/chip.dart:101`, `message_text.dart:339`). Medium, both. Fixed in #733.

- **UX4. Onboarding and sign-in waste a fifth of the desktop viewport** (`onboarding-desktop-light.png`). Medium, desktop.
  Both are two-column layouts whose left column is flat background carrying only the wordmark, roughly 540 of 2800px, on the first screens a new self-host operator or invited teammate ever sees.
  Fix: use the column to orient a first-time user, or narrow it so the pane does not read as unfinished. Effort: medium.

- ~~**UX5. The DM header shows a generic glyph instead of the correspondent's avatar**~~ (`dm-desktop-light.png`). Low, both. Fixed in #748.
  The DM header now shows the correspondent's `AppAvatar` (their initials, keyed on the DM's name), the same identity every other member-naming surface shows; a text or voice channel keeps its hash or speaker icon.

- ~~**UX6. A fresh account reads its own presence as "Status: Unknown"**~~ (`settings-desktop-light.png`). Low, desktop. Fixed in #815.
  The presence row's value is a deliberately-null session echo (there is no read-back endpoint, and seeding a default could tell a hidden user they are visible), so option 1 - seeding a default - was ruled out. The row's `unknownLabel` now renders that null as "Not set", a deliberate "no choice yet" rather than the default "Unknown" that read as an error against the online/away/dnd/offline vocabulary.

- ~~**UX7. `textDisabled` sits below the AA text floor**~~ (`design_system/lib/src/app_tokens.dart:173`). Low. Won't fix (see #733): disabled text is deliberately WCAG 1.4.3-exempt - `contrast_test.dart` reports its ratio rather than gating it.

## CI and release

- ~~**CI1. `desktop-clients.yml` publishes release assets with no `environment`**~~ (`.github/workflows/desktop-clients.yml:42,96`). Medium. Fixed in #668.
  Both jobs now declare `environment: release`, rather than taking the entry's other option of documenting an exemption. The exemption `main-builds.yml` documents rests on it being a continuous build that must not sit waiting on a reviewer gate; `desktop-clients.yml` is triggered by a `client-v*` tag, so it is a real release and that reasoning does not carry over.

- ~~**CI2. `docs/ci.md` documents 15 of 21 workflows.**~~ Low. Fixed in #668.
  The count was right and the list was short. Six were missing, not four: the entry named `client-macos-ci`, `client-windows-ci`, `desktop-clients` and `copr-publish`, and missed `advisory-watchdog` and `verify-release-checks`.
  All six now have rows, with sections for what a row cannot hold. `scripts/check-ci-docs.py` gates it in both directions, because a doc fix alone drifts again: a workflow with no row, and a row naming a workflow that no longer exists. It is wired into `hygiene.yml`.

## Test quality and coverage

- **TEST1. The client ships with no automated pixel regression coverage at all** (`design_system/test/golden_matrix_test.dart:13`). Medium.
  Both pixel mechanisms are gated behind environment variables that are set nowhere in CI: `SLIMM_GOLDENS` and `SLIMM_UI_SNAPSHOTS` appear only in `scripts/ui-snapshots.sh` and `scripts/ui-capture.sh`, both developer-run, and never in `.github/`.
  Reference images are deliberately uncommitted, so the diff has nothing to compare against even if the gate were set.
  This supersedes T3 of the 2026-07-29 audit, which recorded the same gap for one golden; it is in fact every golden and every snapshot.
  TEST2 is what that missing coverage let through.
  Fix: generate references on the CI runner with `--update-goldens`, commit them, and set both variables in `client-ci.yml`. Effort: medium.

- ~~**TEST2. The snapshot suite captures a blank Roles screen and nothing notices**~~ (`client/packages/app/test/ui_snapshot_test.dart:170`). Medium. Fixed in #737 (the harness now fails a stable-blank surface; the blank Roles screen itself was already closed by #166).

- ~~**TEST3. `message_row_test.dart:403` skips its only real assertion via an `if` guard.**~~ High. Fixed in #667.
  Worse than recorded, and worth keeping written down. The guarded finder looked for an `InkWell` inside the emoji panel, which that panel has never rendered - its tiles are `EmojiGrid` cells wrapped in a `GestureDetector` - so it matched zero widgets from the day the test was written and the tap never once ran. The entry assumed the block ran until the regression returned; it had never run at all.

- ~~**TEST4. `touch_targets_test.dart:78` loops over possibly-empty finders.**~~ Medium. Fixed in #667.

- ~~**TEST5. `sync_message_ops.rs:179` loops over a possibly-empty ops array.**~~ Medium. Fixed in #667.

- ~~**TEST6. `canvas_ops/feed.rs:267` reads source text without the shared scrubber.**~~ Medium. Fixed in #667.
  The recorded fix was wrong and the entry is kept rather than quietly corrected. It proposed narrowing to `support::function_body(&source, "pub async fn list_canvas_ops(")`, which would have scrubbed the comments and also dropped every other function in the file from a whole-file check. `support::code_only` over the whole file was shipped instead: same scrubbing, no loss of scope.

- ~~**TEST7. `refresh_token_index_plan.rs:105` reads source text without the shared scrubber.**~~ Medium. Fixed in #667.
  The recorded fix would have broken the test, which is the more useful half of this entry. It proposed `support::code_only`, but the join being searched for lives *inside* a query string literal, and that scrubber blanks strings as well as comments, so it would have destroyed the thing being matched. The fix anchors to a real `sqlx::query*!` call site instead, which proves the text is in a live query rather than merely outside a comment.

- ~~**TEST8. `e2e_voice.py:177` cannot fail on the case it names.**~~ Medium. Fixed in #667.

- ~~**TEST9. `e2e_voice.py:224` repeats TEST8's shape.**~~ Medium. Fixed in #667.

- ~~**TEST10. `composer_test.dart:248` loops over a possibly-empty finder.**~~ Low. Fixed in #667.
  The entry copied the desktop sibling's `findsNWidgets(5)`; the phone density renders three, because poll and code fold into the "+" sheet.

- ~~**TEST11. Reserved-username refusal has no integration coverage**~~ (`http/auth.rs:278`). Low. Fixed in #754.
  `registration_gate.rs` now posts `/auth/register` with `everyone`/`here` (and mixed case) over the real router and asserts 400, and that a refused reserved name leaves the deployment unclaimed. Mutation-checked: removing the handler's `validate_username` call fails it.

- ~~**TEST12. `test_seed_settle.py:220` asserts over a possibly-empty Counter.**~~ Low. Fixed in #757.
  The no-double-vote test now asserts the vote Counter is non-empty before checking `all(count <= 1 ...)`, so the check can no longer pass vacuously if `_vote_on_poll`'s RNG-gated early return ever skipped every vote. The fixed seed still records votes, so the guard is satisfied rather than vacuous.

- ~~**TEST13. `test_check_workflow_red_streak.py:215` matches against unstripped source.**~~ Low. Fixed in #756.
  The workflow-URL assertion now strips comment-only lines from the script before matching, so a stale comment naming the wrong workflow can neither satisfy the `assertIn` nor break the `assertNotIn`. Verified by adding such a comment and confirming it is ignored.

- **TEST14. The infinite-animation `pumpAndSettle` trap is a convention, not a harness** (`client/packages/app/test/member_profile_eject_test.dart:149`). Low.
  `AppSpeakingRing` starts an unbounded `repeat(reverse: true)` on call join, which hangs `pumpAndSettle` forever unless the test sets `disableAnimations: true` first.
  Every current test does this correctly, but each does it by hand, so the next one to mount a speaking-capable widget hangs instead of failing.
  Fix: fold the guard into a shared pump helper. Effort: small.
  The shared helper now exists (`test/support/reduced_motion_harness.dart`'s `reducedMotionApp`, added in #827) and `member_profile_eject_test` uses it; the entry stays open because the other speaking-capable tests keep their own local reduce-motion wrappers, several of them router-based rather than this `MaterialApp`-home shape, so they are migrated as they are next touched rather than rewritten in one sweep.

- ~~**TEST15. Four tests use a deprecated semantics API**~~ (`client/packages/app/test/canvas_activity_panel_test.dart:125`). Low. Fixed in #755.
  The named files had partly moved on already; the deprecated `tester.binding.pipelineOwner` remained in `context_menu_region_reachability_test.dart`, `voice_settings_camera_test.dart`, `message_row_author_profile_test.dart` and `desktop/window_menu_button_test.dart`. All four now read `tester.binding.renderViews.first.owner!.semanticsOwner!`, the pattern the already-migrated files use; each test still dumps and asserts over the real semantics tree, so a wrong accessor would fail rather than pass.

## Rejected or corrected during verification, so nobody re-finds them

- **"The canvas op log grows without bound because `place`, `move` and `reorder` rows are never swept." Rejected.**
  `canvas_ops_sweep.rs`'s module doc states `place` rows are deliberately never touched, because `list_canvas_ops` reads a placed object straight off the `place` row's own seq: the row is the object, and deleting it removes the object from every future replay rather than trimming history.
  `canvas_op_clock.rs:100` separately records that `move` and `reorder` are never swept.
  The sweep's documented scope is reclaiming `remove`, `clear` and `restore`, so there is no contradiction with the roadmap either.
  The finding cited that same comment as evidence of the bug.

- **"`voice::roster`, `space::read` and `members::list_removed` are misclassified and should charge `Class::Read`." Corrected, see API1.**
  The facts are right and the fix is backwards: `Class::Read` is tighter than `Class::Write`, `(20, 2)` against `(30, 5)`, so the swap would make the polled roster refuse sooner.

- **"`showIncomingCall` is the only channel in the package with no `try`/`catch`." Corrected, see PLAT1.**
  Three of the four platform channel files are unguarded; only `apns_token_channel.dart` catches anything, so this is the package norm rather than an outlier, and the "unlike every sibling" framing that justified a high severity is false.

- **"Settings, Space settings, Roles renders completely blank." Corrected, see TEST2.**
  The capture really is blank, but `roles_screen_test.dart` passes and asserts on the `@everyone` row, so the screen renders correctly under an ordinary widget test.
  This is a snapshot-harness settling gap, not a product defect.

## Progress

Nothing fixed yet.
All 70 items are open as of 2026-08-14.
