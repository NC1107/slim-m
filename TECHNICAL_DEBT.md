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
16 are now closed, leaving 54 open, of which 4 are high: CP2, MOD1, MOD2 and MOD5.
Two of the four high items left are product decisions rather than defects, so they are owner calls and not simply unstarted work; MOD5 says so in its own entry.

Closed on 2026-08-14, in order: DB1 to DB4 in #663, TEST3 to TEST10 in #667, and CP3, CI1 and CI2 in #668.
CP1 is partly fixed in #668 and stays open, downgraded to Medium.
MOD3 closed on 2026-08-15 in PLACEHOLDER_PR.

Nine findings from the same day's CI audit closed in #665, and are not itemised here because that audit was reported separately: the client path filter that matched every push, the red-streak watchdog failing its own job, `secrets: inherit` on the copr job, the deployed image carrying no sbom or provenance, the apt list duplicated across three workflows, two SPDX headers labelling client tooling AGPL, the SPDX gate passing on an empty file list, three stale concurrency keys, and unpinned base images.

Worth reading before picking anything here: of the thirteen items worked on since this audit was written, six had a recorded fix that was wrong - TEST3 understated the damage, TEST6 and TEST7 each proposed a fix that would have broken the test, CP3's would have shipped a resubscribe bug, CP1's would have frozen the presence tiles during a pan, and MOD3's would have let a re-removed member sign straight back in.
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

- **SRV1. The reaction summary is recomputed once per connected client** (`http/ws/authorization.rs:314`). Medium.
  `authorize()` runs independently per open WebSocket for every hub broadcast, and the `ReactionsChanged` branch calls `store.reactions_for_message(message_id, ctx.user_id)` fresh each time with no cache, so N viewers cost N of these per reaction.
  Downgraded from High on 2026-08-14 after measuring it, and the original wording overstated it in two ways worth keeping written down. It is one query rather than a round trip per reactor: both sides are primary-key scans on `WITHOUT ROWID` tables, about 0.18ms on a realistic seed, of which the blocked-reactor subquery is roughly 17%. And the cost that actually scales is contention for a pool capped at 8 connections shared server-wide, which is a smaller and different claim than "N database round trips".
  Note when fixing: the result is deliberately viewer-specific, because blocked reactors are excluded per viewer, so a single shared cache across connections would be wrong. This is not a theoretical objection - `hub/event.rs:49` says so in its own doc comment, decision record 0009 fixes it as an invariant, and commit `7cf0618b` fixed exactly this leak once already.
  Fix: compute once per event and filter per viewer, or cache per message keyed on the blocklist inputs. Effort: medium.

- **SRV2. The retention sweep holds the write lock across roughly 1000 sequential round trips** (`store/message_retention.rs:129`). Medium.
  `prune_messages_before` selects up to 200 candidates, then loops doing a per-message `UPDATE ... RETURNING`, an `insert_message_op` (two round trips), and `release_message_attachments` (a SELECT, a DELETE, and a SELECT per linked attachment), all inside one `begin_write()`.
  Fix: batch the soft-delete with `WHERE id IN (...) RETURNING`, then one multi-row op insert and a batched attachment release, as `canvas_ops_apply.rs` already does after M7 in the 2026-08-11 review. Effort: medium.

- **SRV3. `list_dm_conversations` costs 1 + 2N round trips** (`store/dms.rs:234`). Medium.
  It pages the DM list, then loops calling `user_profile` and `unread_count` per conversation, on every `GET /dms` and inside `evict_from_voice`.
  A batched `Store::user_profiles(ids)` already exists in `store/users.rs` and is unused here; no batched unread count exists yet.
  Fix: collect ids, call `user_profiles` once, add a batched unread count grouped by channel the way `permissions_batch.rs` batches overwrites. Effort: small.

- **SRV4. Attachment serving buffers whole files and supports no Range requests** (`media/mod.rs:196`). Medium.
  `read_attachment` reads the file into a `Vec<u8>` and `serve()` builds `Body::from(bytes)`, with no `Range`, `If-Range` or `Accept-Ranges` handling.
  `video/mp4` and `video/webm` are in the content-type allowlist, so a video player seeking re-downloads the whole file, and one large attachment is fully resident in memory per concurrent request.
  Fix: stream via `ReaderStream` over an async file handle and add single-range support. Effort: medium.

- **SRV5. A retried invite redemption either falsely fails or burns a second use** (`store/invites.rs:286`). Medium.
  `spend_invite`'s conditional UPDATE guards the invite's own `uses`, `max_uses`, expiry and revoked columns, but never whether this caller already redeemed this code.
  On a `max_uses=1` invite whose response was lost, the retry reports failure for a redemption that succeeded; on a limited invite it spends a second real use for one logical redemption.
  `tests/invites.rs` never covers it: its use-limit test redeems as two different users.
  Fix: record redemptions per `(code, user_id)` so a repeat call from an already-redeemed user is a no-op. Effort: small.

- **SRV6. The stale-call sweep evicts participants one at a time** (`lib.rs:228`). Low.
  `sweep_stale_voice_calls_at` awaits `voice.remove_participant` per stale pair, each a real HTTP POST to LiveKit, so a blip that expires many heartbeats in one tick serialises N round trips.
  Fix: fan out with a bounded `for_each_concurrent`. Effort: small.

## Server: API contract

- **API1. The `Class::Read` rate-limit class does not mean what three call sites assume.** Medium.
  `Class::Read` is documented for unauthenticated metadata reads (`/version` and its capability list) and carries a *tighter* budget than `Class::Write`: `(20 burst, 2/s)` against `(30, 5)`.
  57 authenticated routes charge `Class::Write` regardless of whether they read or write, making `Write` the de-facto authenticated class; the outliers are `http/metrics.rs:55` and `http/analytics.rs:128,180`, which charge an authenticated admin read against the unauthenticated class.
  The live consequence is on `voice::roster` (`http/voice.rs:260`), whose own doc comment tells clients to poll it on an interval while it shares the `Write` bucket with token mint, heartbeat and kick.
  Moving it to `Class::Read` would tighten it, not loosen it, so this is a decision rather than a swap: either widen `Read` to mean "cheap authenticated read" and move the read-only GETs onto it (`voice::roster`, `http/space.rs:43`, `http/members.rs:242`), or give polled reads their own class and move `metrics` and `analytics` back onto `Write`. Effort: medium.

- **API2. Channel, category and role creation are not idempotent** (`http/channels.rs:190` and siblings). Medium.
  They take no client-supplied UUIDv7 id, unlike `sendMessage` and `createPollMessage`, and none of the three tables has a `UNIQUE` constraint on `name` the way `custom_emoji.name` does.
  A retried POST after a lost response creates a real duplicate row, against the documented UUIDv7-idempotent-writes architecture.
  Fix: accept a client-supplied id and return the existing row on retry, or add a `UNIQUE` index on name as a cheaper backstop. Effort: medium.

- **API3. 62 of 113 documented operations omit the 429 response** (`schema/openapi.yaml`). Medium.
  Counted by parsing every `operationId` block for a `"429"` key.
  `getMe` runs through `AuthedLimited<READ>` (`http/users.rs:211`) and can 429 but documents only 200 and 401, while `sendMessage` documents 429 for the same shape.
  Fix: add the shared `TooManyRequests` response to every rate-limited operation, with a gate in the spirit of `tests/openapi_contract.rs` so the two cannot drift again. Effort: medium.

## Architecture

- **ARCH1. The attachment wire shape is defined three times** (`http/gifs.rs:298`, `http/attachments.rs:51`). Low.
  `store::AttachmentSummary` is canonical and `http/message_dto.rs::AttachmentDto` already carries a `From` impl, but `attachments.rs` and `gifs.rs` each hand-roll the same four fields from the same locals.
  A field added to the canonical shape needs three synchronised edits, and missing one makes the upload or GIF-select response diverge from list and fetch for what the client treats as one object.
  Fix: delete both private DTOs and return `message_dto::AttachmentDto::from(summary)`. Effort: small.

## Client: package boundaries and architecture

- **CA1. `data`'s public barrel leaks drift's generated row classes** (`client/packages/data/lib/data.dart:12`). Medium.
  It exports `Channel`, `Message` and `ChannelCategoryRow`, which implement drift's `Insertable<T>`/`DataClass`, so most of `app` is transitively coupled to drift's interfaces without importing drift.
  This is the coupling that makes the local-store swap, or the Postgres move CLAUDE.md anticipates, expensive.
  Fix: give `data` plain DTOs that repositories map drift rows into at the boundary, so generated types never leave `lib/src/`. Effort: large.

- **CA2. A widget imports drift directly and bypasses the store API** (`client/packages/app/lib/src/widgets/channel_rail.dart:8`). Medium.
  It imports `package:drift/drift.dart show Value` and calls `Channel.copyWith(..., categoryId: Value(categoryId))` at line 239 instead of going through `CategoryStore`/`MessageStore`.
  The widget layer now also has to change if drift is replaced, and category-reorder write logic can drift between here and the store.
  Fix: add a store method for "move channel to category at position" and call that. Effort: small.

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

- **CS1. The whole presence map is watched with no `.select`** (`client/packages/app/lib/src/providers/presence_controller.dart:22`). Medium.
  State is one `Map<String, PresenceState>` for every user, replaced wholesale on every `PresenceChanged`, and `member_pane.dart:60` watches the whole map.
  Any single member's presence flicker reruns `AppMemberPane.build`, re-sorts and re-groups the entire roster, and rebuilds every row.
  Fix: give each row its own `presenceControllerProvider.select((m) => m[userId])`. Effort: small.

- **CS2. `VoiceState` bundles a high-churn participant list with low-churn flags** (`client/packages/app/lib/src/providers/voice_state.dart:33`). Medium.
  `participants` updates on every join, leave, mute and speaking change while sharing one state object with `cameraEnabled`, `deafened` and `error`, and a workspace-wide search finds zero `voiceControllerProvider.select` call sites across roughly ten consuming widgets.
  Fix: split `participants` out, or add `.select`-based derived providers for the flags each widget actually reads. Effort: medium.

- **CS3. The same `watchChannels()` StreamBuilder is reimplemented in six widgets** (`client/packages/app/lib/src/screens/dm_call_button.dart:27`). Medium.
  `rail_call_summary.dart:56`, `voice_strip_indicator.dart:130`, `compact_channel_app_bar.dart:58`, `command_palette.dart:233` and `channel_rail.dart:152` each open their own stream over the entire channels table and filter to one id in the builder, each with slightly different null handling.
  Fix: add a `channelByIdProvider(String id)` family over one shared stream provider and route all six through it. Effort: medium.

## Client: performance

- **CP1. Canvas presence tiles rebuild on every pan and zoom frame.** Medium, was High. Partly fixed in #668.
  The recorded fix must not be applied as written, and that is the useful half of this entry. It proposed keeping camera-only changes away from the presence layer, via a separate notifier or a `ValueNotifier<Camera>`. The layer reads `document.camera` and hands it to every tile, and `document.worldView` to its own visibility pass (`canvas_presence_layer.dart:236,246`), so a camera change it does not see is tiles frozen in place while the canvas pans under them.
  What was actually wrong is narrower and is fixed: `setCamera` notified unconditionally, including when `_clamp` returned the camera already held, which is what a gesture run into a world edge or a zoom stop does for as long as the finger stays down. Measured before the fix, twenty pointer events held against an edge produced twenty notifications and twenty full presence rebuilds of an unchanged frame. `setViewport` immediately above it had always had that guard.
  What remains, and why this stays open at Medium: on a camera that really did move, the layer still re-derives tile keys, the identity map and the on-canvas rects, none of which depend on the camera at all - only `_visibility.update` and the tile transforms do. Splitting the camera-independent prefix from the camera-dependent suffix is the real fix and is untouched here. Effort: medium.

- **CP2. Dragging one canvas object repaints the whole scene** (`client/packages/voice_canvas/lib/src/canvas_document.dart:236`). High.
  Every pointer-move during a drag or resize calls `moveObject`, which reallocates a full `Float32List` copy of the object's entire point array and reindexes the spatial grid, then `refresh()` recomputes scene culling.
  Fix: give the actively-dragged object a thin ephemeral overlay painter for the duration of the drag, the isolation the package already applies to in-progress pen drafts, and defer the reallocation to drag end. Effort: large.

- ~~**CP3. Per-participant platform-channel calls fire on every room event**~~ (`client/packages/rtc/lib/src/local_audio.dart:65`). High. Fixed in #668.
  Confirmed as recorded, and the cost is real rather than a local field write: flutter_webrtc's `enabled` setter invokes `mediaStreamTrackSetEnable` with no equality check of its own, and for an audio track it also fires that track's `onMute`/`onUnMute`.
  The recorded fix was keyed wrongly and would have shipped a bug, which is worth keeping written down. It said to cache per track *id*. A resubscribe reuses the publication and its sid, so an id-keyed cache reads as a hit and skips the reapplication that exists precisely to catch a track that came back at source-default volume - the invariant the file's own header documents. The shipped cache is keyed on the platform track object, which a resubscribe replaces (`addSubscribedMediaTrack` builds a new `RemoteAudioTrack` around a new `MediaStreamTrack`), so it correctly misses. Mutation-testing the id-keyed version fails the resubscribe test.

- **CP4. Every camera tile rebuilds on every room event** (`client/packages/rtc/lib/src/camera_view.dart:60`). Medium.
  Each `CameraView` and `ScreenShareView` subscribes to the whole `room.events` stream and calls unconditional `setState` with no relevance filtering, so cost is tiles times events.
  Fix: filter each tile's listener to the event kinds that can change its own track, or route through one shared provider. Effort: small.

- **CP5. Cursor labels re-shape text on every paint** (`client/packages/voice_canvas/lib/src/canvas_live_painters.dart:268`). Medium.
  `CursorPainter._paintLabel` builds a fresh `TextPainter`/`TextSpan`/`TextStyle` and calls `.layout()` for every visible remote cursor on every paint, and the layer repaints on every remote cursor update, every camera pan and every glide tick.
  Fix: cache a `TextPainter` per cursor id keyed on label and colour, re-laying out only when either changes. Effort: small.

- **CP6. `splitStroke` is O(L squared) per completed stroke** (`client/packages/voice_canvas/lib/src/stroke_splitter.dart:54`). Medium.
  It grows a candidate one point at a time and re-encodes the whole quantised list from scratch at each step to find the byte-budget boundary, synchronously on the UI isolate at stroke end.
  Fix: track running encoded length and bounds incrementally, making the search O(L). Effort: small.

- **CP7. The transcript's live-watched window grows without bound** (`client/packages/app/lib/src/providers/channel_history.dart:153`). Medium.
  `loadOlder()` grows `state.window` by up to 50 per scroll-back with no ceiling, and `channel_screen.dart:345` passes it straight through as the `limit` of a drift `.watch()` query that re-runs on any write to the messages table anywhere in the app.
  Fix: cap window growth, or stop re-deriving the whole window from one growing-LIMIT stream. Effort: medium.

- **CP8. Every incoming message rebuilds the entire channel rail** (`client/packages/app/lib/src/widgets/channel_rail.dart:151`). Medium.
  The rail watches `store.watchChannels()`, a drift watch over the whole `channels` table, while `_advanceCursor` (`message_store.dart:436`) writes `channels.cursor` on essentially every applied message in any channel, invalidating that table-level watch.
  Fix: move the per-channel read cursor out of the row the rail's list query watches. Effort: medium.

## Client: data layer

- **CD1. Catch-up writes are unbatched** (`client/packages/data/lib/src/message_store.dart:306`). Medium.
  `applyMessages` loops `applyMessage`, each doing its own select, insert-on-conflict and `_advanceCursor` select plus update: four sequential awaited round trips per message, on the path a user hits returning from offline.
  `upsertChannels` in the same file already batches the equivalent write via `db.batch()`.
  Fix: batch the existence check, write inserts via `db.batch()`, and advance each channel's cursor once at the end. Effort: medium.

- **CD2. The local store has no retention policy** (`client/packages/data/lib/src/message_store.dart:27`). Medium.
  Every delete path fires only on a server-signalled reset, a delete, or sign-out; nothing evicts by age or count, so the local sqlite or OPFS store grows for the life of an account as history pagination pages older messages in.
  Fix: cap cached rows per channel, or evict channels not opened recently, the way the avatar and attachment byte caches already bound themselves. Effort: large.

- **CD3. The seq-adjacency rule is implemented twice** (`client/packages/app/lib/src/providers/message_ops_sync.dart:84`). Low.
  `liveOpDecision` and `CanvasSync.applyLive` (`canvas_sync.dart:251`) independently implement the identical three comparisons, and `liveOpDecision`'s own doc comment says it "should read as identical" to the other.
  A future change to the gap-detection rule has to land in both by hand.
  Fix: extract one shared helper both call. Effort: small.

## Client: code quality and platform

- **CQ1. Channel extras are hydrated on mount but not on channel switch** (`client/packages/app/lib/src/screens/channel_screen.dart:125`). Medium.
  `_hydrateExtras()` seeds reactions, attachments, polls and thread summaries and runs only from `initState`, while `didUpdateWidget` resets every other piece of per-channel state without re-invoking it.
  The main channel route always rebuilds the State, but `ThreadScreen`'s modal route carries no `Page` key and does reuse it across a `channelId` change; on that path already-synced messages' extras never render until an unrelated live event touches them.
  `ThreadScreen`'s own `_ensureThreadChannelRow` is `initState`-only in the same way.
  Fix: call `_hydrateExtras()` again in the `oldWidget.channelId != widget.channelId` branch. Effort: small.

- **CQ2. `home_shell.dart:429` reinvents `firstOrNull`.** Low.
  `_ChannelTitle.build` uses `.firstWhere((c) => true, orElse: () => null)` while `ConversationPane.build` does the identical lookup with `.firstOrNull` 200 lines earlier in the same file.
  Fix: use `.firstOrNull`. Effort: small.

- **PLAT1. Platform channel calls are unguarded, including one on the FCM background isolate** (`client/packages/platform/lib/src/call_notifications.dart:41`). Medium.
  `showIncomingCall` awaits `invokeMethod` with no `try`/`catch`, and it runs from the FCM background isolate's top-level handler where there is no outer catch either, so a `PlatformException` or `MissingPluginException` silently loses an incoming-call notification.
  This is the package norm rather than an outlier: `call_lifecycle_channel.dart` (three calls) and `notification_tap_channel.dart` (one) are equally unguarded, and only `apns_token_channel.dart` catches anything.
  Fix: guard all four channel files uniformly, starting with the background-isolate path, and assert a thrown platform exception is swallowed. Effort: small.

## Moderation and community safety

Judged against real moderator scenarios rather than code style.
Found sound and not listed: the escalation guards, per-channel permission masking, voice ejection, canvas moderation via `MANAGE_CANVAS`, and the conditional UPDATE that stops two moderators both resolving one report.

- **MOD1. There is no way to delete more than one message at a time** (`http/messages.rs:225`). High.
  `deleteMessage` is the only message-delete operation in the whole schema; there is no delete-by-author, no delete-by-time-range and no purge.
  A raid therefore costs one API call and one confirmation dialog per spam message, while it is still arriving.
  Fix: a bounded bulk delete scoped to `MANAGE_MESSAGES`, either an explicit id list or one author's messages in a channel within the last N minutes. Effort: medium.

- **MOD2. A wave of new joiners cannot be found** (`client/packages/app/lib/src/widgets/member_pane.dart:113`). High.
  The only member-facing surface groups by presence and sorts alphabetically, with no search, no filter, no sort by join time and no multi-select.
  Identifying 50 accounts that joined in two minutes means reading an alphabetical list.
  Fix: the client already holds the full roster, so a client-side search box and a sort-by-joined toggle need no server change. Effort: medium.

- ~~**MOD3. Undoing a removal or a timeout erases who did it**~~ (`store/removals.rs:141`, `store/timeouts.rs:94`). High. Fixed in PLACEHOLDER_PR.
  Fixed by `moderation_audit_log` (migration 0048), an append-only table after `canvas_audit_log`'s shape, written in the same transaction as each act. `space_removals` and `member_timeouts` are untouched.
  The recorded fix was rejected, and this is the fifth entry whose prescribed fix would have shipped a bug, so it is worth the space. It said to soft-close with `lifted_at`/`lifted_by`. Three things make that unsafe, each verified against the source: `user_id` is the PRIMARY KEY on both tables, so history needs a surrogate key and a full SQLite table rebuild on each; both writers use `ON CONFLICT(user_id) DO UPDATE`, so re-removing a member would update the lifted row and leave it lifted, returning 204 while the member signs straight back in; and 15 statements read these tables rather than the six implied here, two of which fail closed in ways that are hard to undo on a self-hosted deployment - `sessions.rs:397` gates login, and `roles.rs:313` is the last-administrator guard. A third, `timeouts.rs:158`, is built with `QueryBuilder`, so it is absent from `.sqlx/` and invisible to a review that greps for query macros.
  It would also have reversed a decision written into a shipped, immutable migration: `0020_member_timeouts.sql:9` says "One row per member rather than a history".
  Reasoning and the accepted drift risk are in `docs/decisions/0015-moderation-audit-trail.md`.

- **MOD4. Resolved reports have no read surface** (`store/reports.rs:173`). Medium.
  Distinct from MOD3 and milder than first reported: `resolved_at` and `resolved_by` *are* persisted, so nothing is lost, but `list_open_reports` filters `WHERE r.resolved_at IS NULL` and no second route reads resolved ones, so a resolved report vanishes from every UI.
  Fix: an owner-visible moderation history route and screen. Since MOD3 shipped it now reads resolved reports plus `moderation_audit_log`, which is a single ordered feed rather than two live tables to union and filter. Effort: medium.

- **MOD5. A removed or timed-out member cannot say anything back** (`store/sessions.rs:396`). High.
  `open_session` refuses to create a session for a removed account, so a removed member cannot log in at all, to appeal or even to read why.
  A timed-out member stays logged in but `TIMEOUT_DENY` subtracts `SEND_MESSAGES` everywhere including DMs, so they cannot message a moderator either.
  Whether an in-product appeal path is wanted at all is a product decision, not a defect; recorded because "no route back" is currently implicit rather than chosen.
  Fix, minimally: exempt DM sends to a moderator or administrator from `TIMEOUT_DENY`. Effort: large.

- **MOD6. A timeout's reason is captured but never shown to the person it was issued against** (`http/users.rs:150`). Medium.
  `member_timeouts.reason` is stored, but `MeDto` exposes only `timed_out_until`, so a blocked send surfaces as "you are not allowed to do that" with no reason and no end time.
  Fix: add `timeout_reason` to `MeDto` and show a persistent composer banner naming the expiry and reason. Effort: small.

- **MOD7. The report queue has no live sync** (`hub/event.rs`). Medium.
  No `Report*` hub event variant exists, so a second moderator working the queue learns a report was already handled only by receiving a bare 404 on resolve.
  The conditional UPDATE does prevent a double action landing, so this is wasted work and confusion rather than a correctness bug.
  Fix: publish a hub event on resolution and have the queue drop or grey the card live. Effort: medium.

- **MOD8. A reporter never learns anything happened** (`http/safety.rs:211`). Medium.
  `file_report` returns only the new id; there is no "my reports" route, no resolution notification, and `GET /reports` is gated on `MANAGE_MESSAGES`, so a reporter cannot look up even their own report.
  Fix: a narrow status-only "my reports" read, or a notification when a reporter's own report is resolved. Effort: small.

- **MOD9. Nothing links a returning account to a removed one** (`migrations/0002_core_schema.sql:19`). Medium.
  `users` carries no device fingerprint and no IP, and every IP hit in the server is transient rate-limiter state; nothing records which invite a registration used either.
  Ban evasion is therefore undetectable by anything the product keeps.
  Note the tension with the project's privacy posture: recording IPs is a decision, but recording the invite used is not.
  Fix, minimally: record the invite code a registration came through and surface it on the member and removal records. Effort: small.

## UX and UI

Taken from 302 PNGs rendered from the real widget tree.
Deliberately excluded: everything in `ui-review.md` (accepted motion and feel work), and M8 in the 2026-08-11 review.

- **UX1. Threads hide the parent channel on desktop** (`thread-desktop-light.png`). Medium, desktop.
  A thread opens as a centered modal card over a dimmed scrim, fully obscuring the transcript it belongs to, even at 2800px where there is ample room to dock beside it.
  Discord and Slack, the products the design language names as reference, keep the parent visible.
  Fix: dock the thread as a fixed-width side pane at expanded widths, reusing the member pane's existing dock and reveal mechanism. Effort: large.

- **UX2. Collapsing the rail removes the only access to settings, mic and deafen** (`rail-collapsed-desktop-light.png`). Medium, desktop.
  The collapse removes the entire rail subtree including the user footer, and nothing else in the chrome offers those controls, so a user who collapsed the rail for transcript width cannot mute themselves without expanding it again.
  Fix: keep a minimal persistent strip when collapsed, or relocate mic, deafen and settings into the top chrome. Effort: medium.

- **UX3. The mention pill and search operator chip miss AA contrast** (`design_system/lib/src/components/forms/chip.dart:101`, `message_text.dart:339`). Medium, both.
  Accent text on accent-soft fill measures 4.45:1 in light theme, under the 4.5:1 AA floor that `design-language.md` itself sets as the explicit target.
  Being mentioned is one of the highest-salience moments in the product, so this is the wrong place to be under the line.
  Fix: darken light-theme `accentSoft`, or use the darker `accent` value already reserved for sunken surfaces, which clears 4.97:1. Effort: small.

- **UX4. Onboarding and sign-in waste a fifth of the desktop viewport** (`onboarding-desktop-light.png`). Medium, desktop.
  Both are two-column layouts whose left column is flat background carrying only the wordmark, roughly 540 of 2800px, on the first screens a new self-host operator or invited teammate ever sees.
  Fix: use the column to orient a first-time user, or narrow it so the pane does not read as unfinished. Effort: medium.

- **UX5. The DM header shows a generic glyph instead of the correspondent's avatar** (`dm-desktop-light.png`). Low, both.
  Every other surface naming a specific member shows their real initials avatar; the DM header is the one place that identifies a person by name and declines to show their face.
  Fix: use the correspondent's `AppAvatar`. Effort: small.

- **UX6. A fresh account reads its own presence as "Status: Unknown"** (`settings-desktop-light.png`). Low, desktop.
  "Unknown" reads as an uninitialised or error value against the online, away, dnd and offline vocabulary used everywhere else, and it is the first thing a new admin sees about their own account after onboarding.
  Fix: default a freshly created account's presence to whatever bootstrap actually intends, or give "Unknown" a friendlier rendering. Effort: small.

- **UX7. `textDisabled` sits below the AA text floor** (`design_system/lib/src/app_tokens.dart:173`). Low, both.
  2.96:1 on `surfaceBase` and 2.78:1 on `surfaceSunken`, against a 4.5:1 stated target.
  This is almost certainly fine: WCAG exempts disabled controls, and the token's own doc comment argues disabled and de-emphasised text must stay distinguishable.
  Fix: no code change, just one line in that doc comment confirming the exemption is deliberate so a future contributor does not "fix" it. Effort: small.

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

- **TEST2. The snapshot suite captures a blank Roles screen and nothing notices** (`client/packages/app/test/ui_snapshot_test.dart:170`). Medium.
  Every Roles capture, in both themes and every viewport, renders the modal chrome (title, back arrow, add button) over an entirely empty body, though the fixture wires three roles and sibling admin screens render correctly in the same run.
  This is a harness gap and not a product defect: `roles_screen_test.dart` passes and asserts on the `@everyone` row, so the screen renders correctly under an ordinary widget test.
  The real problem is that `expectSettled`, whose stated job is catching a placeholder standing in for content, did not fire, so the Roles surface is entirely unguarded by the snapshot suite.
  Fix: settle the roles provider on that surface (`roles` is absent from `_nestedResolveSurfaces`) and make `expectSettled` fail on an empty content area rather than emitting a blank PNG. Effort: medium.

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

- **TEST11. Reserved-username refusal has no integration coverage** (`http/auth.rs:278`). Low.
  The `@everyone` and `@here` refusal is covered only by a unit test calling `validate_username()` directly; no test posts `/auth/register` with those names over the real router, so a regression that stops the handler calling the validator would pass the suite.
  Fix: add a registration case asserting 400. Effort: small.

- **TEST12. `test_seed_settle.py:220` asserts over a possibly-empty Counter.** Low.
  `all(count <= 1 ...)` is vacuously true if no votes were recorded, and `_vote_on_poll` has an RNG-gated early return that could skip voting entirely.
  Not failing today because the seed is fixed.
  Fix: assert the Counter is non-empty first. Effort: small.

- **TEST13. `test_check_workflow_red_streak.py:215` matches against unstripped source.** Low.
  It asserts over the whole script text including comments, the shape the source-reading-gate rule forbids; harmless today only because no comment contains either literal.
  Fix: strip comment lines, or anchor to the `gh api` line. Effort: small.

- **TEST14. The infinite-animation `pumpAndSettle` trap is a convention, not a harness** (`client/packages/app/test/member_profile_eject_test.dart:149`). Low.
  `AppSpeakingRing` starts an unbounded `repeat(reverse: true)` on call join, which hangs `pumpAndSettle` forever unless the test sets `disableAnimations: true` first.
  Every current test does this correctly, but each does it by hand, so the next one to mount a speaking-capable widget hangs instead of failing.
  Fix: fold the guard into a shared pump helper. Effort: small.

- **TEST15. Four tests use a deprecated semantics API** (`client/packages/app/test/canvas_activity_panel_test.dart:125`). Low.
  `tester.binding.pipelineOwner` has been deprecated since Flutter 3.10, repeated in `canvas_fullscreen_test.dart:166`, `rail_drag_handle_test.dart:147` and `context_menu_region_reachability_test.dart:179`.
  Fix: use `rootPipelineOwner.semanticsOwner`. Effort: small.

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
