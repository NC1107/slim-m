# slim-m knowledge base

Development context and project state for slim-m.
This is the durable memory of the project: read it first when picking the work back up.
Kept concise on purpose; the deep detail lives in `docs/`.

## What this is

slim-m is a lightweight, self-hostable, Discord-style messaging platform (text, voice, screen share) with an infinite collaborative Voice Canvas as its signature feature.
Flutter client, Rust server, and a separate Go push relay.
The name "slim-m" is a working placeholder; a final name is chosen before 1.0.

Core reading, in order: [docs/BRIEF.md](docs/BRIEF.md), [docs/STRATEGY.md](docs/STRATEGY.md), [docs/ROADMAP.md](docs/ROADMAP.md), and the decision records in [docs/decisions/](docs/decisions/).

## Moderating a member: timeouts, removal, and per-participant volume (2026-07-29)

The four sections the member profile popover rendered as absent, built out.
Server side in PR #136, client in #138.
Read this before touching permission reads, the login path, or anything to do with call audio.

**A timeout is a subtraction where permissions are read, not a check per verb.**
`TIMEOUT_DENY` (`store/timeouts.rs`) mirrors the shape `BLOCKED_DENY` already used in `store/dms.rs`, and it is applied at the exit of `permissions_in_channel` (wrapping *both* its DM early return and the evaluator), in `base_permissions`, and in both batched paths in `permissions_batch.rs`.
That is what makes it reach send, react, attach, polls, pins and the LiveKit token with no edit to any of those files.
`USE_CANVAS` is deliberately spared: that one bit means view *and* draw, so subtracting it would blank the canvas rather than make it read-only, and splitting the bit is Phase 6 work.
Expiry is a comparison against the clock at every read, so a timeout lapses by arithmetic and nothing has to run on time for somebody to get their voice back.

**Checking that design adversarially before building it found four real bypasses**, two of which predate the feature entirely and are fixed in #136.
Message *edit* gated on `VIEW_CHANNEL` and then let the author through with no further bit, so anyone denied send could rewrite anything they ever posted and republish it to the whole channel - a complete substitute for sending. It needs `SEND_MESSAGES` now; delete is left on authorship alone, because a delete publishes an id rather than words.
Attachment *upload* asked for no permission whatsoever; it needs `ATTACH_FILES` deployment-wide now, with the per-channel check still happening when the id is attached.
The other two were mine to close in the design: DMs return before the evaluator, and the batched paths run their own copy of it.

**A LiveKit token is a bearer credential the server cannot revoke**, so both timeout and removal also call `remove_participant` for every voice channel. Taking `SPEAK` away only affects the *next* token; `voice.rs`'s own `kick` doc had already recorded this and it was still easy to miss.

**"Remove from Space" is a ban in behaviour and the docs say so.**
There is no membership row to delete - one deployment is one community and holding an account *is* membership - so it has to be a durable row (`space_removals`), because a version that only closed today's sessions would be undone by signing in again.
It does *not* stop the same person registering a fresh account on an open Space; nothing short of identity verification would, and `deploy/README.md` says that rather than implying a guarantee.
Authorship is deliberately untouched: no `deleted_at IS NULL` join learns about this table, or a removal quietly becomes the account deletion it is not.
`administrator_count` (`store/roles.rs`) **did** have to learn about it - it filtered only on `deleted_at`, so without that a deployment could be left with zero usable administrators and no recovery path, silently, with every existing test green.

**Authorization is the two bits that already existed and had never been spent**: KICK_MEMBERS for the temporary act, BAN_MEMBERS for the durable one.
On top of the bit, permission containment stands in for the role hierarchy this product does not have: you may only moderate somebody whose *granted* permissions yours already contain.
Without it KICK_MEMBERS is enough to silence every administrator one at a time.
It reads granted rather than effective permissions on purpose, so timing somebody out is not itself what makes them look junior enough to time out again.

**`Helper.setVolume` works on three of the six platforms, and the two failure modes are opposite.**
This is the one worth not rediscovering.
livekit_client 2.8.1 has no per-participant gain API; flutter_webrtc (already a direct dependency of the rtc package) does. But:
- **Android, iOS, macOS work.** Their native track lookups fall back to scanning the peer connection's transceivers, so a remote track is found.
- **Linux and Windows throw.** They share `common/cpp`, whose lookup scans only a `remote_streams_` map filled by the Plan B `OnAddStream` callback; LiveKit uses Unified Plan, where that never fires, so the map is always empty and the call returns "Unable to find provided track". flutter_webrtc's wrapper does not catch it, unlike every sibling in that file.
- **Web silently does nothing.** It becomes `applyConstraints({'volume': ...})`, which no browser honours, and `applyConstraints` constrains a track's *source* - a remote track's source is the RTP receiver. LiveKit plays remote audio through an `HTMLAudioElement` it does not expose, so there is no other handle.

`supportsParticipantVolume` (`rtc/lib/src/audio_gain.dart`) is therefore derived from the platform and the slider is absent where it would do nothing.
Note what that means: **Fedora and the web build are two of the three that cannot do it**, so the feature is invisible in both environments this project tests in locally, and real only on a phone.
Gain also has to be reapplied on every room event, because it lives on the platform track object and a resubscribed track returns at 100% with nothing to say so; `LocalAudioState.applyTo` is the one place that happens.

**Role names are not unique, and matching by them was a live bug.**
Nothing in the schema constrains `roles.name`, so a client deciding "does this member hold that role" by name lights up every role sharing one.
`UserProfile` carries `role_ids` beside `roles` now (names render badges, ids make assignments), and both role sheets match on the id.

Three smaller traps this hit:

- **`client/packages/api/lib/api.dart` exports through an explicit `show` list, and an extension's methods need the extension's own name in it.** There is a comment saying exactly that directly above the list, and it still cost a while to spot: the symptom is "method isn't defined for the type 'SlimmApi'" while a sibling extension's methods resolve fine.
- **Both hygiene gates enumerate `git ls-files`, so untracked new files are invisible to them.** A local run before the first commit passes and CI then fails on the same tree. Stage before trusting either gate.
- **`scripts/check-comment-cap.sh` was counting Rust `//!` module docs as plain comments**, though its own header exempts them: the awk matched `//` followed by anything that is not `/`. Nothing caught it because the allowlist had been calibrated against the wrong number. Fixed, and the allowlist regenerated at the true counts, which cleared 46 files outright and lowered 98.

## Blocking, and the two halves of it a client cannot do (2026-07-30)

The 2026-07-30 audit's only finding where the product stated a protection that did not exist.
`blocksProvider` had three references, all inside `personal_account_sections.dart`, and it was `autoDispose`, so the block list was alive only while the settings pane listing it was mounted.
Outside that pane nothing filtered anything, while a successful block answered "Blocked. Their messages are hidden for you."
The server delegated on purpose - `store/safety.rs` said "the client filters with this rather than the server stripping messages" - to a client that did not filter.

**The filter is at read time, never at fetch time, and that is the load-bearing choice.**
A blocked author's messages still arrive and still land in the local database; they are dropped where they would become UI.
Filtering `/sync` instead would mean they never arrive, and since `/sync` filters purely by `seq`, only a full channel reset could ever bring them back - so "unblocking restores their messages" would become false.
`visibleChannelMessagesProvider` is the one stream `ChannelScreen` can get at, so the filter is a property of the data rather than a `where` clause somebody has to remember per render site.
`blocksProvider` is session-warm (not `autoDispose`), watched at the shell so it loads with the app, and it empties on sign-out - the local database is one file for the whole app, so a block set outliving a sign-out would silently hide messages from whoever signed in next on the device.

**Read state must keep counting a blocked author.**
Their message is hidden, not unreceived.
`VisibleTranscript.newestSeq` is computed before the filter for exactly this reason: a marker advancing only past what is shown leaves a channel lit as unread forever the moment a blocked person has the last word, with nothing in the API able to clear it.

**Two surfaces are out of the client's reach and are handled server-side, per viewer.**
Reaction counts carry no reactor ids on the wire, by design, so there is nothing client-side to match on; `reactions_for_messages` already took the viewer, so excluding blocked reactors is one predicate, and an emoji whose only reactors are blocked is absent rather than sitting at zero.
Push reaches the device before any filter runs, and a phone buzzing for a message the app then hides is worse than no filtering, since it reports exactly when the blocked person spoke; `push::message_recipients` is a named function now rather than three steps inside a fire-and-forget task, because it is the whole security decision and a task reporting to nothing but the log cannot be tested.
Both stay view choices rather than moderation actions: nothing is removed for anybody else and the blocked user is never told.
Migration 0022 indexes `user_blocks(blocked_id)`, since the reverse lookup runs on the message write path.

**Three defects in the first version of this were found by an adversarial review, not by any test, and the worst one was created by the fix itself.**
Recording them because each is a shape that will recur.

- **Changing what a shared function means to one caller changed it for every caller.** `reactions_for_messages` gained a `viewer` parameter's teeth, and `http/reactions.rs`'s `publish` had been passing `UserId::generate()` with a comment saying any id yields the same public counts. That was true before and false after: the broadcast started fanning one *unfiltered* tally to everybody, and the client replaces its cached tally with whatever a frame says, so a single reaction from a blocked person put their count back on screen. `Event::ReactionsChanged` carries ids only now and the tally is derived per receiving connection, exactly as `PresenceChanged`'s status already was. `tests/blocking_live.rs` drives a real socket for it, because `blocking_reach.rs` drives the store and the store was right.
- **A second implementation of the same feature does not get fixed by fixing the first.** `command_palette.dart` runs its own message search beside `channelSearchProvider` and renders the body and the author's name; it went unfiltered. Its message-search path also turned out to have *no* test at all, because the palette harness started at `/channels` with nothing selected and the palette only searches when a channel is.
- **`sessionProvider.changes` fires on every access-token rotation, not just sign-in.** Refetching the block list on each one made routine rotation a race against an in-flight block: a `GET /blocks` sent before the block landed and answering after it silently unblocked somebody the app had just confirmed. The listener compares the *user id* now, and a generation counter drops any answer a newer state has superseded.

**Gating the transcript on the block list having loaded was tried and reverted.**
It is the obvious way to stop a launch painting a blocked author for a frame, and it costs more than it buys: it couples every channel's first paint to an unrelated network call, and an empty stream standing in meanwhile stops `pumpAndSettle` ever settling, which hung several existing shell tests.
The residual is recorded in `blocks_controller.dart` with the real answer named - a block set persisted beside the session, known synchronously at launch, with the fetch only correcting it.
Search, pins and typing filter against whatever is known for the same reason, so all four surfaces behave alike.

**A `StreamProvider` body must return the stream, not `yield*` it.**
Cancelling an `async*` generator that delegates to a drift query stream deadlocks a widget test: drift defers a cancelled stream's cleanup onto a zero-duration timer, and the fake clock only advances on the next pump, which never comes.
The symptom is the test hanging until the harness kills it and flutter_tools crashing with "Cannot close sink while adding stream", which names nothing relevant.
Mapping the stream directly has none of that and is shorter.

Also done here: report and block existed twice, once per subject kind, with byte-identical copy in `member_actions.dart` and `channel_message_actions.dart`; they are one implementation in `widgets/safety_actions.dart` with two call sites now.
The blocked list rendered raw 36-character uuids where names belong (it reads as corruption, and two of them cannot be told apart) and resolves through `userProfileProvider`.
`unblockUser` threw out of an async `onPressed` with no `try`, so a failure reached nobody.
The member popover offers Unblock rather than Block for somebody already blocked, since offering Block again reads as the block having failed.
And the copy says only what is true: messages, reactions and typing go, notifications stop, and the person stays in the member list.

Known rough edge, left deliberately (2026-07-30): an existing DM with somebody you then block stays in the rail and opens as an empty transcript with no explanation.
It is already frozen server-side (`store/dms.rs` denies SEND, ADD_REACTIONS and ATTACH_FILES in both directions), so nothing new can arrive; what is missing is the client saying so instead of rendering a blank channel.
Presence and the member row are also unfiltered on purpose - hiding somebody from the roster would make the member count wrong and take away the row the unblock lives on.

## The nine-specialist audit, and seeing a shared screen (2026-07-29)

Nine parallel specialist reviews (five code, four screenshot) over the running product; the consolidated report with everything found, fixed, and deliberately deferred is [docs/research/nine-specialist-audit-2026-07-29.md](docs/research/nine-specialist-audit-2026-07-29.md).
Read that before the next audit pass so nothing is re-found.
A fifth round implemented the error-states spec beside a component-usage audit: `AppErrorState` is the persistent inline failure that replaces vanishing toasts (27 sites carried a failure only as a SnackBar), `buildTheme` overrides `ColorScheme.error` with the danger token so the two reds that meant "danger" cannot diverge again, and danger is outlined everywhere - never a filled button.
One spec item stays unimplemented on purpose: distinguishing an expired invite from an invalid one would undo the server's deliberate uniform answer that stops code mining.
A fourth round implemented the design agent's motion spec; the durable constraints it surfaced: row height must never animate (density is layout), the hidden member pane must unmount (it fetches while built), a button-theme `textStyle` replaces inherited styles wholesale, and the hold-progress tint rides Flutter's own long-press timeout because `GestureDetector` is what publishes the semantic action.
A second round the same day covered what the first under-covered: the snapshot harness's `_surfaces` map (`ui_snapshot_test.dart`) now renders all 12 routed screens, not just the two shell ones, so `scripts/ui-snapshots.sh` yields the whole app (60 renders) and the settings/admin screens sit under the CI overflow gate.
Two harness facts worth keeping: `fixtureContainer` must call `SharedPreferences.setMockInitialValues` (the voice settings screen reads it and the platform channel has no host in a test), and the fixture's fake HTTP catch-all answers `[]`, so any endpoint whose real answer is a map needs an explicit case or the screen renders its error state - which is exactly how it exposed 14 sites interpolating `$e` into visible copy.
What to know before touching the affected code:

**Screen share viewing exists now, and the seam shape matters.**
Publishing a share and seeing one are separate halves, and only the first had ever been built - the e2e proved subscription at the SFU while the viewer's pane rendered a roster glyph and nothing else.
`VoiceSession.screenShareViewFor(identity)` returns the live view as a plain `Widget`, so no LiveKit type crosses the rtc package seam; the real renderer (`screen_share_view.dart`, deliberately not exported) listens to room events itself because the track routinely arrives a beat after the roster flips to sharing.
Every fake implementing `VoiceSession` had to grow the method; the app-test fakes return a keyed `SizedBox` so widget tests can assert the stage mounted for the right participant.
Verified end to end: the e2e's `bob-peer-sharing-screen.png` shows the sharer's actual screen. Note `scripts/e2e.sh` reuses a cached web build unless `E2E_REBUILD=1` - a verification run after a client change *must* set it, or it screenshots the old build (that cost one confused cycle).

**The batched permission paths must stay equivalent to the per-user one.**
`viewers_among` (push fan-out: many candidates, one channel) and `visible_channels` (the rail: one caller, many channels) live in `store/permissions_batch.rs` and run the same pure `evaluate()` as `permissions_in_channel` after loading the role context and overwrites with a bounded number of queries.
`tests/permissions.rs` carries an equivalence test for each, driving every precedence rule plus the ADMINISTRATOR bypass, DMs, and a nonexistent channel; any change to one path has to keep those green, and a new batched consumer should reuse these rather than looping `has_permission`.

**Recorded correctness debt, still open:** message edits and deletes made while a client is offline never reconcile - edit does not advance `seq`, `/sync` filters purely by `seq`, and deleted rows are filtered out of deltas, so only a reset heals it.
That needs a designed protocol answer (op watermark or tombstones in the sync response), not a patch.
The per-socket WS fan-out permission cost (four queries per event per connection) is the other big recorded item; the safe fix is a per-connection visibility cache with real invalidation on role and overwrite edits.

Smaller traps this pass hit: `Opacity` over a whole row silently destroys AA contrast (the muted `AppListRow` now dims leading/trailing only, and a design_system test pins that); `VoiceSession.join` serializes overlapping calls (both used to pass the room-null check and race one slot); and `SourceType.Window` must never be requested on Wayland from *any* call site - `media_capabilities.dart` had the segfault `desktop_sources.dart` already documented.

## Motion, haptics, and the device-testing polish pass (2026-07-29)

Driven by real iPhone use plus a two-reviewer UI/UX pass over the snapshot set.
Read this before touching motion, the message list, or iOS screen share.

**iOS screen share was starting the broadcast twice, and the fix is one flag.**
On iOS LiveKit's `BroadcastManager` shows the system picker and, once the ReplayKit extension is recording, re-invokes `setScreenShareEnabled` to publish the track.
`captureOptionsFor` (`client/packages/rtc/lib/src/voice_session.dart`) left `useiOSBroadcastExtension` at its `false` default, so that second pass never got the `deviceId: 'broadcast-manual'` hint and flutter_webrtc's `getDisplayMedia` tried to start its *own* broadcast, colliding with the running extension ("already broadcasting").
It is now `lk.lkPlatformIs(lk.PlatformType.iOS)` - iOS-only, since on desktop the same branch would clobber the real screen `sourceId`.
The whole `BroadcastExtension` target and its Info.plist keys existed for exactly this path; the options just never opted in.
Still needs a device to confirm end to end (no Mac/simulator here); the root cause is traced through LiveKit 2.8.1's `local.dart` and the flutter_webrtc constraint map, and a `voice_session_test` guards the flag from being hardcoded on (which would break desktop).

**On-mount entrance animations render at opacity zero in the snapshot harness unless it pumps twice.**
A Flutter ticker's first frame is its own `t=0`, so `ui_snapshot_test.dart`'s single `pump(350ms)` caught any `forward()`-on-mount animation before it moved - the voice screen came out blank, which both reviewers flagged as the top bug and neither it nor the desktop header's missing name was real.
The harness now does `pump()` then `pump(350ms)`; two frames settle the entrance without `pumpAndSettle`, which would hang on the states that show a perpetual spinner (`_Connecting`, "catching up").
That fix then surfaced a genuine one the blank was hiding: `_JoinPreview` overflowed a landscape phone, now wrapped in a `LayoutBuilder`/`SingleChildScrollView` that scrolls when short and centres when tall.

New shared pieces, all reduce-motion aware through `AppMotion`:
- `AppMotion` gained `fast`/`base`/`slow` (100/180/280ms) and `entrance`/`exit` curves, the design language's own tokens.
- `AppHaptics` (`selection`/`impact`), guarded to iOS+Android, is the one place a tap becomes a tick; `AppListRow`, `AppButton` and `AppIconButton` now fire it and show a pressed state (a phone has no hover to stand in for the press).
- `AppFadeIn` is a one-shot fade-and-rise for content that swaps within a stable route; `page_transitions.dart`'s `fadeThroughPage` cross-fades shell channel navigation so it no longer teleports.
- Message list: `AppDensity.groupedRowGap` tightens continuations (a run of one author reads as a block), a `DayDivider` marks calendar-day boundaries (Today/Yesterday/absolute, and it breaks a group across midnight), and `ChannelStartHeader` fills the empty band above a short bottom-anchored conversation and is the one place the channel topic shows in the body. The transcript's two presentational widgets live in `message_transcript_widgets.dart` to keep the list file under the review budget.

Two review findings verified as **non-issues**, recorded so they are not re-chased: the footer mic/deafen icons read "low contrast" only because they are correctly disabled when not in a call (WCAG exempts inactive controls); and the phone composer's poll/code actions are not lost but folded into the `+` "More actions" sheet, exactly the overflow the reviewer asked for.
Left for the owner's eye rather than changed solo: header action-button treatment consistency (pin pill vs bare search icon vs filled member toggle), the fallback-avatar colour spread, and a `+` affordance on the DM rail section.

Also fixed here: the member-list toggle showed lit at medium width where the pane is expanded-only and never renders (a dead control); it is now hidden below expanded width. The offline connection bar carries a warn tone and a retry glyph (connecting stays neutral), and the `Ctrl+K` search hint is dropped on touch layouts where no finger can press it.

## The capability handshake (2026-07-28)

Phase 7's "verify a server exposes report and block before connecting and warn if absent" is built.
`GET /version` grew a `capabilities` array, and the sign-in screen names what a server is missing while the choice is still open.

**The list is read off the router, not written beside it.**
`crates/slimm-server/src/http/capability.rs` sends one request per capability through the real `router()` using a method no route can register (`SLIMMPROBE`), and reads the `Allow` header axum puts on the resulting 405.
So routing answers on its own: no handler runs, nothing authenticates, nothing is written, and a report is not filed to find out whether reports can be filed.
A hand-kept list would only ever have proved that somebody remembered to update it, which is the one thing a safety guarantee cannot rest on, and `tests/capabilities.rs` gates that by asserting the derivation can also say *no* (a bare router advertises neither).

**Method, not just path, and that is not a detail.**
`/reports` is mounted twice: `GET` is the moderator's queue (`http/reports.rs`) and `POST` is a member filing one (`http/safety.rs`).
A path-only probe reads a deployment that kept the queue and dropped the intake as still offering reporting, which is exactly backwards.
Mutation-tested: dropping the method check fails `the_moderator_queue_alone_is_not_a_way_to_report` and nothing else.

**Unknown is not absent, on the client side.**
A server older than 0.17.0 sends no `capabilities` key at all, and `Version.safetyTools` reports `SafetyTools.unknown` for that, with its own wording ("too old to say") rather than the accusation.
An unreachable or foreign host renders nothing whatsoever, since nothing has been heard back.
Neither ever blocks the connection: an operator may knowingly self-host without them, so the notice informs and stops there.

Two smaller things this changed on the way past.
`sign_in_screen.dart` held `_pushEnabled` and `_inviteRequired` as separate fields; it holds the probed `Version?` now, which is one piece of state instead of three and made the file 46 lines shorter rather than longer.
The three notices moved into `ServerNotice` (`client/packages/app/lib/src/widgets/server_notice.dart`), which carries its own top gap, so a notice with nothing to say renders as nothing without leaving a hole where its spacer was.
`Version` also moved out of `models.dart` into `models_version.dart`, since 380 lines was already past the review budget before this added to it.

## Reduce motion, and proving presence survives greyscale (2026-07-28)

The two Phase 8 accessibility exit criteria that need no audio are met.
Read this before adding an animation to the client or touching `AppStatusDot`.

**Every animated thing asks one question, and it lives in one place.**
`AppMotion.isReduced` (`client/packages/design_system/lib/src/app_motion.dart`) is `MediaQuery.disableAnimationsOf(context) || MediaQuery.accessibleNavigationOf(context)`, and `AppMotion.reduced(context, d)` returns `Duration.zero` or `d`.
Both signals, not just the first: a screen reader being on means a loop is movement nobody sees and a transition is only a delay in front of the next announcement.
A new animation routes its duration through that call or it is not honouring the setting; the durations themselves still sit at their call sites, and folding them into the design language's named `fast`/`base`/`slow` steps is a separate visual change nobody has asked for yet.

**The speaking ring is the one thing allowed to loop, and it did not loop at all before this.**
Decision 0004 specifies a pulse, and `AppAvatar` was drawing a plain static border, so the "under reduce-motion it becomes static" half was vacuously true and the cue it was meant to preserve did not exist.
`AppSpeakingRing` (`components/core/speaking_ring.dart`, split out rather than added to `avatar.dart`, which was near the 300-line budget) pulses the ring's alpha on a reversing controller, and under reduce-motion stops it at full strength and adds `AppSpeakingGlyph`, three level bars on a disc at the avatar's bottom-left corner.
The glyph is drawn rather than set as a Lucide icon because it renders at roughly 10dp, where a 1.5px-stroked outline closes into a smudge; it is not emoji chrome.
It mounts only while somebody is actually speaking, so nothing is left ticking.

**Busy spinners are deliberately left spinning.** iOS and Android both keep their own activity indicators moving under reduce-motion, and a frozen spinner reads as a hung app rather than as a calmer one, so matching the platform beats a literal reading of the setting. That is written down in `app_motion.dart`'s own doc comment so the next contributor does not "finish the job".

**The presence golden is arithmetic, not an image, and that is the strong version.**
`test/presence_desaturation_test.dart` renders each `AppPresence` through the real widget, rasterises it, converts to Rec. 709 luma, binarises against the surface, and compares the five silhouettes pairwise.
Binarised rather than compared as grey levels on purpose: two states painted the same shape in two different hues *do* differ in greyscale, and accepting that would be measuring the colour cue this test exists to remove.
It runs everywhere, unlike a reference image (see `golden_matrix_test.dart`'s note); a PNG of the desaturated strip is written by the same file behind `SLIMM_GOLDENS`.
The tightest real pair is offline against appearing-offline at roughly 2.2% of the box, which is the 2px bar struck across the ring and does not scale with the dot, so the floor sits at 1%.
Two things it needs: the surface has to be painted *inside* the repaint boundary, or transparent pixels read as ink in a light theme and as background in a dark one; and `toImage()` has to run in `tester.runAsync`, for the reason the Fedora section below gives.

What makes it worth having over `core_test.dart`'s existing check: mutating the away triangle to draw a disc while leaving `AppStatusDot.shapeOf` alone leaves `core_test.dart` green and fails this in all three themes.

## A per-channel voice roster (2026-07-28)

The rail could only show who was in the one call already joined; every other voice channel looked empty even with people talking in it.
`GET /channels/{channelId}/voice/roster` (`crates/slimm-server/src/http/voice.rs`) closes that, backed by a new `VoiceService::list_participants` (`crates/slimm-server/src/voice/roster.rs`, a sibling of `voice/mod.rs` split out for the line budget) that calls LiveKit's `ListParticipants` the same way `remove_participant` already called `RemoveParticipant`.

Three things worth knowing before touching it again.

**Appear-offline is enforced here too, not just in `presence.rs`.**
Being in a LiveKit room already reveals your identity to everyone else already in that room - that half cannot be hidden, the SFU has to tell participants about each other to let them hear one another - but this route is the *preview* a caller who has not joined yet can query, and it must not become a second way to learn a hidden user is online.
A participant whose `presence_visibility` is `Hidden` is dropped from the response for every viewer but themselves, checked per participant against the store, the same structural treatment `status_for` gives every other surface.

**Unknown, empty, and not-configured are three different answers, not one.**
A 501 means this deployment has no SFU at all (hide the roster).
A 503 means one is configured but could not be reached just now (show nothing, but do not clear what was already known).
A 200 with an empty list means the room was actually checked and nobody is in it.
`tests/voice_roster.rs` drives all three against a real (or deliberately unreachable) room service; the response contract test cannot exercise the 200 case at all, because the fixture's SFU is `wss://sfu.invalid`-shaped on purpose (see `world.rs`), so `listVoiceRoster` sits in `UNCOVERED` for the same reason `kickVoiceParticipant` already did.

**Cost is handled client-side, not server-side.**
There is no cache in front of LiveKit; the answer instead is that `voiceRosterProvider` (`client/packages/app/lib/src/providers/voice_roster.dart`) is a `StreamProvider.autoDispose` keyed per channel, polling on a 15-second `Timer.periodic` that only exists while a rail row for that channel is actually on screen, and `VoiceChannelRow` never watches it at all for the one channel already joined, since that one already has live participant data for free.
`Timer.periodic` rather than a bare `Future.delayed` loop, deliberately: it is the only shape `ref.onDispose` can actually `.cancel()`, and a widget test proved the difference - the `Future.delayed` version left an uncancellable timer pending after every test that ever got a successful fetch.

Found and fixed along the way: `ui_snapshot_test.dart`'s fake HTTP client had a catch-all fallback of `<Object>[]` for any unmatched path, the right empty answer for a list endpoint and the wrong shape entirely for this one, so the full-shell snapshot test crashed with a type-cast error the moment this route existed.
It now answers the roster path with `{"participants": []}` explicitly.

## The design-alignment push (2026-07-26)

The UI was aligned to the Claude Design visual identity review, and the features the design assumed were built to back it.
Read this before touching the client or adding a server feature the UI needs.

The design system is a real component library now: `client/packages/design_system/lib/src/components/` holds core (avatar, badge, button, icon button, kbd, status dot), forms (input, chip, toggle, segmented control, slider) and surfaces (card, callout, code block, list row, menu).
Tokens split into `app_tokens.dart` (colour), `app_typography.dart` (the six-step scale, three weights, stopping at 600) and `app_metrics.dart` (spacing, radii, control sizes, the two shadows, density).

**Eight server features were built because the design needed them and nothing backed them**: presence (with appear-offline), typing indicators, pinned messages, polls, direct messages, attachments and avatars, a server identity fingerprint, and channel topics plus member roles on the member list.
Migrations 0008 through 0014.

Things worth knowing before changing any of it:

- **Appear-offline is enforced structurally, not by filtering.** The `PresenceChanged` event carries only a user id, never a status, and the real status is derived per receiving connection at send time through one pure function. A hidden user's true state is never present in the payload that fans out. Do not "optimise" this by precomputing the status into the event.
- **`checkInvite` answers expired, spent, revoked and never-issued identically**, so codes cannot be mined. The client models this as a sealed `InviteCheck` where `InviteUnusable` carries no fields at all, so metadata is unreachable except by matching the usable case. A test asserts the four responses are byte-identical.
- **The server identity fingerprint is Ed25519, not derived from the TLS certificate.** A plain-HTTP LAN self-host has no certificate, and a reverse proxy's certificate churns on every renewal. TOFU protects every connection after the first, not the first one; the docs say so in those words rather than overselling it.
- **A DM is a channel with kind `dm`.** Teaching `permissions_in_channel` about that kind was enough to make push fan-out, WebSocket delivery, sync and search all DM-aware with no change to any of those files. Membership of the pair is the only thing granting access: the ADMINISTRATOR bypass is deliberately skipped, and there is a test for exactly that.
- **Attachment content types are sniffed from the bytes**, never taken from the upload's header or filename, and avatars re-sniff at serve time so a stored type cannot drift from the file. Fetches are permission-checked; an unguessable URL is not access control.
- **Litestream does not back up attachments.** It replicates the SQLite file only, so a restore returns messages and their attachment references but not the bytes. `deploy/README.md` says so.
- **`Config` has a `Default` impl now.** It did not, and 38 files built it as a struct literal, so every new setting was a 38-file edit. That cost is why the attachments work first read its settings straight from the environment, creating a second configuration mechanism. A test asserts `Config::default()` matches deserializing an empty config, because that drift is the one failure this refactor could introduce silently.

**Check `0002_core_schema.sql` before adding a table.** Two of these features turned out to have dormant schema waiting for them: the `attachments` and `message_attachments` tables, and `channels.topic`. Both were written speculatively in the very first schema pass and never referenced by a single line of code since. Attachments reused its tables (they were already content-addressed by sha256, which gives deduplication for free); `0014_channel_topic.sql` is a documented no-op marker recording the discovery rather than a redundant `ALTER TABLE`.

After this push every table in 0002 is wired except the canvas pair. `canvas_objects` and `canvas_ops` are referenced in exactly one place, `store/sessions.rs`, which anonymises their `author_id` on account deletion. That is correct and deliberate: account deletion has to cover a table the moment it exists, not the moment it is used. The canvas itself is Phase 5 and 6 work.

Known gaps, deliberately left.
**Date every entry in a list like this one, and strike it through rather than deleting it when it closes.**
Five notes in this file went stale inside two days (2026-07-28): four recorded bugs that were already fixed, the claim that the overwrites screen "silently redirects to Deny", and the emoji picker below.
A stale gap costs more than a missing one, because it sends work at a problem that no longer exists and gets quoted forward into later documents as though still live.
A struck-through entry with the date it closed is what stops the next reader trusting it:

- ~~**Live WebSocket frames omit poll, reaction and attachment data.**~~ Fixed 2026-07-28, and the note above it was wrong about the cost. It claimed the fix needed "a database read inside the hot fan-out path or reshaping a widely shared struct"; it needed neither. The send handler already read the attachment summaries for its own response, just *after* publishing, so reading them once before it and handing them to both costs nothing. `Event::MessageCreated` carries them beside the row rather than the row growing a field, so nothing else holding a `Message` changed. Reactions stay absent and that is correct: a message that has just been created cannot have any.
- **Webhook and bot authorship is not built.** The design shows a CI message; an integrations system is well past beta scope, and the UI marker stays rather than being faked.
- ~~**Emoji picking is a single placeholder reaction.**~~ Already stale by the time this was checked, 2026-07-28: PR #76 (2026-07-27) built a real one. `emoji_picker_panel.dart` is a searchable, grouped, keyboard-navigable grid over the `emojis` package's catalog, with the deployment's own custom emoji and a recent shelf both feeding the same `PickerEmoji` grid; see `emoji_catalog.dart` and `emoji_picker_test.dart`.

### Seeing the UI, and the font trap it exposed

The shell was compared against the design by rendering it in a throwaway widget test at the design's own 1400x880 and writing a PNG, because there is no nested display server on this box and a native Wayland window cannot be raised or captured by `xdotool`. That harness is not committed: it produces the image correctly every run but does not shut down cleanly, and a test that fails when run is worse than none. Recreating it is cheap, and worth it before any further visual change.

Three things it takes to make such a render truthful, each of which silently produces a wrong picture rather than an error:

- **Load the real fonts with `FontLoader`.** The test binding ships a placeholder face, so every glyph is a filled box.
- **Load the Lucide font too**, from `packages/lucide_icons_flutter/assets/lucide.ttf`. An unloaded icon font renders every icon as an empty square, which reads as a layout bug.
- **Seed a session.** Signed out, the client refuses each read before sending it, so the member pane and rail render error states rather than their real layout. Then dispose the container *before* unmounting, or `SyncController`'s reconnect timer keeps the test alive forever.

What it found is the reason to bother: **the fonts were never bundled at all.** `AppFonts` named IBM Plex Sans and Mono, `app_typography.dart` claimed in a doc comment that they shipped with the app, and no font file existed in the repo. On this machine both resolved to Noto Sans, so the *monospace* family was rendering proportional - every code block, timestamp, keycap and the server fingerprint. The faces are now bundled under `client/packages/design_system/fonts/` (OFL, licence alongside), and note the family name must be package-qualified as `packages/slimm_design_system/IBM Plex Sans` or it resolves to nothing from the app package and falls back silently. `buildTheme` also names the family now; it never did, so everything outside `AppText.code` was using Flutter's default regardless.

Two accessibility rules the components enforce and test, worth not breaking:

- **Presence is never colour alone.** Five states, five silhouettes: filled disc, triangle, notched square, hollow ring, and a slashed ring for appearing offline. Contrast ratio is deliberately *not* asserted between two status hues, because it measures luminance only and the away amber sits within 1.04:1 of the dnd red while being obviously a different colour. Shape carries it.
- **`focusRing` and `accentFill` are the same value in every theme**, which the design intends. Focus is told from selection by shape: selection is a fill plus a marker, focus is an outline ring. An earlier doc comment claimed the two were different colours; they never were, and a test written against that claim found it.

## The Phase 5 canvas spike (2026-07-27)

Both halves are done and both bets hold, but neither for the reason the roadmap assumed.
Full findings in [docs/research/canvas-spike-server.md](docs/research/canvas-spike-server.md) and [docs/research/canvas-spike-client.md](docs/research/canvas-spike-client.md).
Read those before writing production canvas code in Phase 6.

**An R-Tree that prunes nothing is the trap here, and it is silent.**
On a database that has never been `ANALYZE`d, which is every slim-m deployment, SQLite plans the natural `JOIN` as the rtree module's rowid-equality strategy: it reads every object in the channel and probes the index once per row to confirm what it already had.
Right answer, zero pruning, 7.1x slower than no index at all.
Running `ANALYZE` while investigating makes the planner pick correctly on its own, which is exactly how this ships broken.
`CROSS JOIN` pins the order, and `tests/canvas_index.rs` reads the SQL out of `src/store/canvas.rs` rather than a copy and asserts the plan, so a later edit that reintroduces it fails.

**Neither index is justified by the stated soft caps.**
At 20,000 objects a plain scan takes 1.56 ms server-side, and client-side a brute-force linear scan culls in 26 us against the grid's 16 us, on a 16.6 ms frame budget.
The server index earns its place past the cap, across several canvases in one index, and under a pan firing continuously; the client grid saves 11 us per frame and costs a rebuild, no incremental update, and an 8.5x regression when objects cluster in one cell, which is the normal way people use a shared board.
Whether the client keeps the grid at all is a Phase 6 decision; the adaptive seam reports which branch it took, so it is a runtime call rather than a rewrite.

**Both fall over on viewport shape, not object count.**
Server-side the index loses past roughly four screens of viewport (0.8x at eight screens, 0.6x for the whole world).
Client-side, zooming out probes cells by world area while object count stays flat: 880,704 probes at zoom 0.001, an 11.8 ms frame, 71% of budget. A linear-scan fallback when cell span exceeds object count turns that into 72 us.

Two smaller results worth keeping: the client cell size should be 1024, not the planned 2048, and sensitivity is asymmetric so err small; and `StreamProvider` values are not observable until the event loop turns, so a stream physically cannot deliver inside the frame that produced it. The no-Riverpod-in-the-render-loop rule is a correctness property, not a performance preference.

Known gaps the spike leaves for Phase 6: the client index has no `remove` or `move` and a full rebuild costs 1.3 ms, while dragging is the canvas's primary interaction; and a soft delete does not advance an object's `seq`, so no cursor over the viewport endpoint can report a removal. Removals belong to the canvas op stream, and patching that into the object cursor would create a second ordering authority.

## Cross-origin access, moderation UI, and channel administration (2026-07-27)

**`SLIMM_CORS_ALLOWED_ORIGINS`** (`crates/slimm-server/src/config.rs`, `crates/slimm-server/src/cors.rs`) adds an opt-in CORS layer so a web build of the client can reach the server.
Unset or empty means no layer at all, not an empty allow-list: an empty `CorsLayer` would still intercept preflights and answer them without an allow header, which is a different, worse thing than refusing to add it.
A native client sends no `Origin` header and is unaffected either way.
`*` is refused at startup rather than accepted as a shortcut: a self-host usually sits on a network the operator's own browser can route to and the internet cannot, and an open policy would hand every page they visit the run of that perimeter.
`Access-Control-Allow-Credentials` is never sent: this API authenticates with a client-attached `Authorization: Bearer` header, not a cookie, so credentialed mode would buy nothing here while adding the ambient authority that turns one wrong origin into a full account takeover.
A malformed origin fails the process at startup, named in the error, rather than surfacing as a browser console error later.
Full operator-facing writeup in `deploy/README.md`.

Settings gained a "Community management" section (`_ModerationSection` in `settings_screen.dart`), hidden entirely, including its divider, when the caller holds none of the four gating permission bits.
Four screens: a reports queue (MANAGE_MESSAGES), invites (CREATE_INVITE), roles (MANAGE_ROLES), and per-channel permission overwrites (MANAGE_ROLES).
The overwrites screen cannot show an existing overwrite because the API has no `GET` for one, only set or clear, and it says so in a callout rather than faking current state.
Its "Allow" option is unavailable when the caller lacks that bit themselves, the same restriction the server enforces.
`AppSegmentedOption` carries a `disabled` flag for it, which dims the label to `textDisabled` and wires no tap handler at all rather than accepting the tap and having the caller drop it: an option that merely does nothing still reads as available and still reports itself as a button to assistive tech.

Channel management (create, rename or clear topic, delete) is gated on MANAGE_CHANNELS, read from `GET /me`.
Delete refuses the deployment's last non-DM channel (409) and is idempotent on one already deleted.
There is deliberately no client-side duplicate-channel-name handling: `store/channels.rs` and the migrations confirm the server has no uniqueness constraint on channel name, so there is no such failure mode to surface.

The message context menu (long-press or right-click) adds edit, delete, and pin/unpin, each gated per-message on authorship and MANAGE_MESSAGES.
Found and fixed along the way: `SyncController` never handled the `message.deleted` live event, so a message deleted by another device (or looped back from this device's own delete) never left the local store.

An audit of empty/loading/error states fixed several places that rendered a failure identically to a genuine empty result: channel search (a failed fetch no longer reads as "no matches"), pinned messages (a failed load now says so and offers a retry, except on 403, which explains the denial instead), the member pane (added a retry), and the channel message list (empty now distinguishes "still catching up", "offline", and genuinely empty by reading `SyncController`'s status).
The voice join preview gained a `VoiceState.retryable` flag: a 501 (no voice configured) or 403 (permission denied) hides the Join button instead of inviting a retry that is guaranteed to fail the same way again.
That flag also fixed a real cross-channel leak: `VoiceController` is one instance for the whole app, so an error from channel A was being shown, and could block joining, in channel B's preview; both the displayed error and the button-hiding are now gated on the error belonging to the channel currently being previewed.

**This section's "not yet fixed" list is closed, 2026-07-28.** All six entries were re-checked against main by a fan-out that had to cite file and line for every claim; four had already been fixed and the notes had outlived them, and the last two were fixed then. Recording that because the cost was real: a stale backlog sends work at problems that no longer exist, and two of these had been quoted forward into later documents as though still live.

What had already been fixed, and where to look if it recurs: the `ref.invalidate`-after-dispose sites all carry a `mounted` guard now; the `OverlayPortal` children are wrapped in `Positioned`; `manage_channel_sheet.dart`'s delete reads the router before the async gap; the revoked-session redirect lands on sign-in with the server address intact; and `voice_controller_test.dart`'s retry test already drives one controller twice (its doc comment says why, and is what stops somebody "simplifying" it back).

## Driving the Apple Developer portal (2026-07-28)

The App Group, the extension App ID, and the broadcast profile were all created by driving `developer.apple.com` over the Chrome DevTools Protocol, on an isolated profile with its own `--user-data-dir` and `--remote-debugging-port`.
Worth knowing before doing it again, because three things cost real time:

- **Synthetic JS clicks do not work.** `element.click()` and a dispatched `MouseEvent` both leave the portal's Save doing nothing, silently. Use `Input.dispatchMouseEvent` through CDP, which produces trusted events, and click by an element's bounding-box centre.
- **Save raises a "Modify App Capabilities" confirmation modal**, and nothing on the page says so. Two apparently successful saves had saved nothing; only reloading and re-reading the row caught it. Verify every write by reloading, never by the absence of an error.
- **The App Group description rejects hyphens** (`@ & * ' " - .` are all refused), so it is "slimm Shared" rather than "slim-m Shared". The identifier itself takes dots fine.

**The thing to know before touching a capability at all: adding or removing one invalidates every provisioning profile containing that App ID.**
Enabling App Groups on `top.npcserver.slimm` turned `slim-m App Store Distribution` Invalid immediately, and the next iOS release would have failed to sign.
It has to be regenerated and its GitHub secret updated in the same sitting.
Match the certificate by sha1 fingerprint against `~/.secrets/slim-m/slimm_distribution.p12` rather than by the expiry shown in the list, which renders in local time and reads a day earlier than the certificate says.

There is an App Store Connect API key (`asc-api-key-A94NDY63N8.p8`) that can create App IDs and profiles without a browser, but the issuer id lives only in a write-only GitHub secret, and the public API has no App Groups endpoint at all. The portal is the only route for the group.

## Running the Fedora build, and what it found (2026-07-28)

The rpm was installed and used, and it found nine defects in one sitting.
Read this before touching desktop voice, emoji rendering, or the icons.

**Screen share on Linux could never have worked, and the reason is not in our code.**
`flutter_webrtc`'s `GetDisplayMedia` matches its `source_id` against a `sources_` vector that is only ever populated by `GetSources`, so a share that names no source fails with `Bad Arguments: source not found!` no matter what else is right.
Proved with a probe against the real plugin on this box: enumerating screens returns one source (`id="1"`), capture with that id publishes a track, and capture without one throws exactly that string.
`VoiceSession.setScreenShareEnabled` takes a `sourceId` now, and `DesktopSources` is the seam that lists them.
**Never enumerate windows on Linux**: `getSources(types: [SourceType.Window])` segfaults the process on Wayland (SIGSEGV, exit 139), and a native crash cannot be caught from Dart.

**Emoji resolve to the monochrome face unless the colour one is named.**
Fedora ships both `Noto Emoji` and `Noto Color Emoji`, and fontconfig hands back the monochrome one, so every reaction chip drew as a hollow outline.
`AppFonts.emoji` is now in `fontFamilyFallback` on the theme and on `AppText.code`.
Verified by rendering the same string three ways through the real engine, not by reasoning about it.

**A `RenderRepaintBoundary.toImage()` in a widget test must be wrapped in `tester.runAsync`.**
Rasterising is engine work the test's fake clock never completes, so the PNG is written and the test then hangs forever holding a finished image. That is the "does not shut down cleanly" problem the earlier throwaway harness hit, and it is why `scripts/ui-snapshots.sh` is committable where that one was not.

`scripts/ui-snapshots.sh` renders the **real shell** at five resolutions in both themes.
`design_system`'s golden matrix renders a synthetic sample of chrome, which is why neither of that pass's two layout bugs was visible to it: the rail's manage button centring against a whole column, and the voice roster never fetching a picture.
The snapshot test also asserts no overflow, and that half runs in CI.
Three things it needs and each fails silently without: real fonts through `FontLoader`, Lucide registered as `packages/lucide_icons_flutter/Lucide` (package-qualified, or every icon is an empty square), and a seeded session.

**Mutation testing a Rust fix needs `touch` after restoring the file.**
`shutil.move` puts the original mtime back, cargo's fingerprint is mtime-based, and it keeps the mutated object file. That cost half an hour chasing a "failure" that was a stale build.

**`/tmp` here is a 16GB tmpfs**, and two Flutter Linux release builds fill it. When it fills, the Bash tool's shell wedges: commands that write to stdout fail with exit 1 while ones that write nothing succeed. Free space and it recovers. Put probe builds under `~/.cache`, not the scratchpad.

Also settled: the rpm's `Recommends` named `gnome-keyring`, which pulled a second unused keyring daemon onto every KDE install. `kf6-kwallet` ships `ksecretd` and `org.kde.secretservicecompat.service`, the same `org.freedesktop.secrets` API libsecret wants, so it is `(gnome-keyring or kf6-kwallet)` now. There is no virtual provide for the capability in Fedora, which is why this has to be a boolean dependency naming both.

And the launcher icon: below 32px the ladder rendered `icon-master-small.svg`, which was the lone square from `glyph.svg`'s reasoning, so a launcher entry had no lattice in it and did not read as this app. Small sizes draw the same mark at 78% of the tile instead of 60%.

### Who can join (2026-07-28)

`space_settings` is one row holding a `join_policy` of `invite` or `open`, read inside the same transaction as the account insert so a concurrent change is not missed.
`invite` is the default and what every deployment keeps on upgrade.
**Unrecognised text reads as `invite` on both sides**, deliberately: a row holding junk, or a value a newer server grows, must not be the reason a Space is open to the internet.
An open Space still accepts a code and still applies the role it grants.
`/version` reports `invite_required` unauthenticated, the same treatment `push_enabled` gets, because the sign-up screen has to say so before an account exists.

Two things the response contract test caught that nothing else would have: a `$ref` to `#/components/responses/RateLimited`, which does not exist (it is `TooManyRequests`), and both new operations having no case in `tests/response_contract/script.rs`. Adding a documented route means adding a case there as well as to `schema/openapi.yaml`.

Found and left alone: **`POST /invites` exposes `max_uses` and `expires_at` only**, so a role-granting invite has no HTTP surface at all despite `Store::create_invite` taking one.

## Driving the client in a real browser (2026-07-27)

A web build plus a local server is now the fastest way to exercise the client end to end, faster than a Linux desktop build and scriptable in a way a real device is not.
It found five real bugs in one pass (below), each confirmed against source and each fixed with a revert-proof regression test.

Setup: build the release server binary, run it with `SLIMM_CORS_ALLOWED_ORIGINS` set to wherever the web build will be served from (a bare origin, no path, see the "Cross-origin access" section above), then `cd client && flutter build web` and serve `client/build/web` with any static file server (`python3 -m http.server` is enough) on that origin.
Two clients on two isolated Chrome profiles (separate `--user-data-dir`, separate `--remote-debugging-port`) is how a two-account flow (DMs, live presence, a second invited member) gets driven without one session's cookies or local storage bleeding into the other.
This box runs several unrelated agent sessions at once; a shared Chrome profile or a shared scratch directory picks up another session's keystrokes and server address, which reads exactly like a garbled-input app bug until you notice it is not yours.
Isolate both, always.

**`chrome-devtools-axi`'s screenshot command does not work against a headless instance on this box**; drive Chrome DevTools Protocol directly (navigate, click, evaluate, and `Page.captureScreenshot`) over the `--remote-debugging-port` instead of going through that wrapper for visual steps.

Confirmed bugs from this pass, in the order found:

- **Any admin sheet that lists roles or members via a synchronous `ref.read` on a cold `FutureProvider.autoDispose` renders permanently empty.** `channel_overwrites_screen.dart`'s role and member pickers did exactly this: no listener gets registered, so `autoDispose` tears the provider down before its fetch resolves, and the sheet's plain closure body never rebuilds anyway. Fixed by two `ConsumerWidget` sheets (`overwrite_target_picker_sheets.dart`) that `ref.watch` instead, matching the pattern `role_assign_sheet.dart` already used correctly. If a new admin picker needs a live list, watch it in a widget, never read it once in a callback.
- **A DM's first message never reached the recipient live.** `MessageStore` has no channel foreign key, so a `MessageCreated` frame for a channel the client had never fetched landed silently and `_advanceCursor` no-opped. `SyncController._applyServerEvent` now checks `store.hasChannel` first and materialises the channel (`_refreshChannelsOnce`, debounced against a burst) before applying the message. The same gap silently hid any newly created channel until reconnect; there is still no `channel.created` event anywhere in the wire protocol, so a next contributor adding one should also delete this workaround.
- **Read state was a dead feature in both directions.** `SlimmApi.markRead` had no call site, so `lastReadSeq` never left 0 and the unread predicate (`cursor > lastReadSeq`) reduced to "has this channel ever had a message", permanently lit. `ChannelScreen` now marks read on render (`_markReadUpToLatest`, guarded per channel so a busy channel does not refire the same seq every rebuild) and `SyncController._refreshChannels` hydrates the marker from the server on every channel refresh, since `/sync`'s `ScopeDelta` carries no read state and `store.clear()` wipes the marker on sign-out.
- **The member pane never learned about a member who joined mid-session.** There is no `MemberJoined` event in `hub.rs`; the fix infers a join from a `PresenceChanged` or a `MessageCreated` naming an id absent from the cached roster (`_memberRosterKeepAliveProvider` in `member_pane.dart`, debounced 500ms, gated on the roster being under the server's member-list page cap so a normal off-page id does not force a refetch). If a real join event is ever added server-side, prefer it and delete this inference.
- **Deleting the currently open channel throws past every catch clause and strands the sheet.** `manage_channel_sheet.dart`'s delete path calls `selectedChannelId(context)` from the sheet's own context after the sheet's navigator already popped out from under `GoRouterState.of`, which finds no router above it and throws `GoError` uncaught. Confirmed in source; **not fixed in this pass** (read the context before the async gap, the way `command_palette.dart` already does, is the shape of the fix).

Confirmed but not fixed, still real:

- ~~**No UI ever called `SlimmApi.report` or `blockUser`.**~~ Closed, but read the blocking section below before trusting the closure: wiring the call up was not the same as blocking working, and it took until 2026-07-30 to notice. The endpoints, wire model, and an admin triage screen all existed with zero call sites in `packages/app`. A concurrent, unrelated change landed in this same working tree while this pass was running and closed it (`report_dialog.dart`, `context_menu_region.dart`, wired into both the message context menu and the member row); it was not this pass's work, so it is not itemised above, but a future contributor should know the gap this pass found is already closed. Its own regression test (`message_row_test.dart`) was missing a `pumpAndSettle` between closing the menu and reopening it for the second tap, which failed the gate deterministically rather than flakily; fixed in the same run, no app code changed.
- ~~**`ContextMenuRegion` repeats the same missing-`Positioned` mistake.**~~ Stale, checked 2026-07-28: the `overlayChildBuilder` in `context_menu_region.dart` wraps its follower in `Positioned` and carries a comment saying why.
- ~~**The server-menu chevron opens a blank, full-viewport overlay.**~~ Stale, checked 2026-07-28 by opening it on a live web build: the Space menu opens correctly and its items are reachable.
- **A context menu is unreachable by keyboard, though not by a screen reader.** `ContextMenuRegion` and `MessageContextMenuRegion` open on `onSecondaryTapDown` or `onLongPress` only. An earlier version of this note claimed that left them with no semantic action either; that was wrong, checked 2026-07-28: `GestureDetector` publishes `SemanticsAction.longPress` for its own `onLongPress`, so VoiceOver and TalkBack have always been able to open these, and `context_menu_reachability_test.dart` now guards that, since it is a side effect of one widget choice and a `Listener` or `excludeFromSemantics` would remove it silently. What is genuinely missing is the keyboard: the rows do not take focus and no key opens the menu, so report, block, edit, delete and pin have no keyboard route. The e2e harness cannot drive them either, for a different reason - it dispatches DOM events rather than semantic actions - so `scripts/lib/e2e_admin.py` covers report and block at the API and says so.
- **A revoked session mid-app drops the user all the way to the bare onboarding root**, not sign-in, losing the remembered server address and showing no explanation, contradicting `router.dart`'s own doc comment. Still open.

Three touched files now exceed the 300-line review budget: `sync_controller.dart` (316, crossed it this pass), `member_pane.dart` (396, crossed it this pass), `channel_screen.dart` (583, already over before this pass). Split before opening a PR from this work rather than adding to them further.

## Current state (2026-07-25)

Phases 0 (foundations), 1 (server and protocol core), and 2 (client shell and text messaging) are complete.
Phase 3 (push relay and notifications) is complete on every exit criterion except the two that need hardware or a Mac; see "Still open in Phase 3" below.

Repositories (public, owner NC1107):
- Core monorepo: https://github.com/NC1107/slim-m (Rust server + Flutter client + shared schema).
- Push relay: https://github.com/NC1107/slim-m-relay (Go, adapted from check-in-relay). Local checkout at `../slim-m-relay`.

Server 0.10.0 is released (2026-07-26) with signed multi-arch GHCR images and native musl binaries; the live instance tracks `latest` and auto-updates.

**Phase 4 is in progress.** Landed: the Linux RTC spike's build answer (livekit_client 2.8.1 and flutter_webrtc 1.4.0 compile and link on Fedora KDE Wayland), LiveKit room capability tokens derived from the permission bitfield, the iOS CallKit and PushKit path with its synchronous-report invariant under test on a macOS CI runner, the `rtc` package's `VoiceSession` behind a room-injection seam with screen-share ceilings, the self-host stack wired to its own SFU with a `compose-smoke` job that boots it, and (PR #50) the voice UI plus a working SFU on the live instance.

PR #50 is worth reading before the next voice change, because both halves were found by using the thing rather than by any gate.
A channel with kind `voice` rendered as a text channel, so there was no way to start or join a call at all; `ConversationPane` now reads the kind from the local store and routes to `VoiceScreen`.
`Routes.settings` was registered, built and tested, and nothing in the app ever navigated to it, which left sign-out, the device list and account deletion unreachable through a whole release.
`client/packages/app/test/route_reachability_test.dart` now fails if any registered route has nothing navigating to it, ignoring the route's own `path:` registration (the evidence that was present for settings the whole time) and comments (its own first draft passed on a comment that merely named the route).

**A voice call has been held, and it is a script now (2026-07-28).**
`scripts/e2e.sh` stands the whole stack up (a real LiveKit SFU, the release server binary, the web build), drives two isolated headless browsers through onboarding, sign-in and a call in one channel, then tears it down.
It covers far more than voice now - messages, mentions, reactions, attachments, avatars, settings, roles, moderation and screen share - and every scenario is checked against the server or the SFU as well as the screen; see [docs/e2e.md](docs/e2e.md).
A full run reaches 36 of the 59 documented API paths and prints the ones it missed, counted from what was really requested rather than from a list kept by hand.
It passes: both participants ACTIVE with an unmuted microphone track published, each subscribed to the other's track, a mute on one side reaching the SFU, and leaving dropping the other side's count.
Mutation-tested by pointing the server at a dead SFU, which fails it at "2 in call" rather than passing quietly.

That closes the criterion that had been open longest, and it closed on the third attempt at the tooling rather than the first.
Three things make driving a canvas app possible at all, each of which fails silently rather than loudly:

- **The accessibility tree is the only handle.** Flutter paints to a canvas and exposes nothing until one click on the `flt-semantics-placeholder` it leaves in the DOM. That click works reliably headless and did not work at all in a headed window on this box, which is the opposite of what you would guess.
- **Only the focused text field has an `<input>`.** Every other field on the screen is paint. So a field is found by its `aria-label` and focused directly, never clicked at coordinates.
- **The same label is painted onto a plain node and a tappable one**, and only the node carrying `flt-tappable` or `role="button"` answers a click. Clicking the other one does nothing and reports success.

**The channel rail publishes no accessibility nodes at all on web.** Not the channel rows, not the section headers, not the search field, not the footer; only the centre pane and the member pane appear in the tree. The harness routes to the channel by URL instead, and says so in a comment rather than hiding it. Nothing in `channel_rail*.dart` excludes semantics and `AppListRow` wraps every row in a `Semantics` with a label, so this is unexplained rather than understood, and it wants a widget-test check of whether the rail reaches the framework's own semantics tree before anyone concludes it is a Flutter web quirk.

**Driving the whole product found two defects nothing else had.**
The avatar crop sheet sized its square viewport from the window's width alone, so on any window wider than it is tall - which is every desktop - the circle was taller than the screen and pushed Cancel and Use picture off the bottom, leaving no way to finish or abandon a crop and so no way to set an avatar at all.
`avatar_crop_sheet_test.dart` asserts both buttons sit inside the window at three sizes.
And a context menu opens on right-click or long-press with no keyboard or assistive-technology affordance, so report, block, edit, delete and pin are unreachable without a mouse; that one is recorded rather than fixed, and `scripts/lib/e2e_admin.py` drives those two at the API and says why.

Still open in Phase 4:
- Voice UX polish: camera pre-toggle. The rail shows a real roster for a channel not yet joined now (see "A per-channel voice roster" above), but the join preview screen itself (`voice_screen.dart`) still does not show who is already in the room before you tap Join; it could reuse `voiceRosterProvider` to close that. The join preview, mic pre-toggle, in-call controls and collapse-to-strip indicator are built.
- Android ConnectionService with a CallStyle notification.
- The runtime half of the RTC spike. `MediaCapabilities.probeAll()` exists but nothing calls it, and the Wayland portal shows a picker, so it needs a human at the screen.
- A real call on an iPhone through TestFlight, and an Android device for the heads-up path. Two web clients is not a phone, and the mobile call path is still untaken.
- The aggregate egress budget, which needs several real clients at once. `scripts/e2e.sh` is the obvious thing to grow into that, since adding clients to it is now a loop rather than a person.

**iOS work does not need a local Mac.** `release.yml` builds the ipa on `macos-latest`, `client-ci` runs XCTest there, `project.pbxproj` is a text file that can be edited directly, and a device build reaches a real iPhone through TestFlight. An earlier note here claimed otherwise; that was wrong, and it is why the phase 3 NSE sat parked longer than it needed to.

### The phase 3 audit (2026-07-25), and what it changed

A nine-dimension review of the whole backbone, with every finding put through an adversarial refutation pass.
It confirmed Phase 3 itself: the sealed-box envelope is content-free and domain-separated, per-device push keys are a dedicated keypair, the relay logs only counts and a key id (never a token or payload), the LAN-only disable path works, and the cross-repo contract test drives a server-generated fixture through the relay's real router.

What it found was mostly Phase 2 debris, and one live hole.
**Registration was never gated on an invite.**
The `TODO(phase 2)` asking for the gate was written before the invite flow existed, the invite flow shipped in phase 2, and the gate did not, so from the moment a deployment was claimed anyone who knew its address could create an account and inherit `@everyone`'s view and send rights.
This was reproduced against the live instance, not inferred: an anonymous caller registered, listed both channels, and read real messages (probe account deleted afterwards).
`register_account` now applies the join policy in the same transaction as the account insert, and the client sends the code with the signup rather than redeeming after it.

Everything else fixed in the same pass, all with tests that fail without the fix:

- Report resolution checked only deployment-wide MANAGE_MESSAGES while listing re-checks it per channel, so a moderator denied it in one channel could not read its reports but could still dismiss them.
- `PATCH .../messages/{id}` charged no rate limit while send and delete both did.
- An idempotent send retry re-fanned-out and re-pushed, outside the debounce window that exists to stop exactly that.
- Three transactions read before writing under a deferred `BEGIN`. SQLite refuses to promote a read snapshot to a writer and returns SQLITE_BUSY immediately, ignoring `busy_timeout`; 24 concurrent sends to one channel failed with "database is locked". They use `Store::begin_write` (`BEGIN IMMEDIATE`) now.
- The client's local database is one file for the whole app and nothing ever cleared it, so the channel list and message text of the account signing out were read straight back by whoever signed in next on that device.
- `docker-compose.yml` fell back to `changeme_api_key` and a matching secret for LiveKit, character for character the placeholders in `.env.example`, and still pinned the very first server release. Both variables now use the `:?` form so compose refuses to start and names the missing one.
- Four workflows ran actions on mutable tags behind a "pin to commit SHA before public" comment in a repo that has always been public.
- Nothing built with `--locked`, so the committed lockfile was advisory and had been recording 0.6.0 while Cargo.toml said 0.8.0.
- No index on `sessions.device_id`, which push fan-out and every device revocation path filter by; and nothing ever deleted expired access tokens, refresh tokens, or connect tickets.
- The FTS5 delete and update triggers issued their `'delete'` unconditionally while the insert trigger is guarded on `is_encrypted`, which corrupts an external-content index. Dormant until E2EE lands, fixed while the table still holds no encrypted rows.
- `/sync` returned messages with an empty `reactions` array while list and search filled it in.
- `schema/openapi.yaml` claimed types were generated from it and CI failed on drift; `models.dart` claimed a contract test asserting every model matches a schema entry. Neither existed. Both headers now state what CI actually gates (method and path, additive-only, valid OpenAPI) and what it does not (bodies, on any of the three sides).
- Push fan-out evaluated permissions for every live user on every message before the debounce was consulted; it starts from who has a usable push registration now.

Measured for the first time, closing the Phase 1 exit criterion that had never been taken: idle RSS of the release binary is 7,296 kB steady and 25,760 kB peak, inside the under-30MB budget.
`perf/baselines/0.8.0.json` is the first committed baseline after eight releases without one.
Note it was taken on glibc while releases ship musl, whose allocator fragments differently under Tokio.

Phase 1 merged so far:
- Core SQLite schema (PR #3): users, auth tables, RBAC, channels, per-scope sequence counters, messages, reactions, attachments, invites, read state, canvas tables, FTS5.
- Identity and message store (PR #8): UUIDv7 newtype ids and a distinct per-scope `Seq`; a `Store` with atomic per-(channel, stream) sequence allocation and idempotent-by-message-id send; edit (FTS re-indexed by trigger); keyset pagination; integration tests for the ordering and idempotency invariants.
- Auth (PR #10): Argon2id (OWASP 19 MiB, semaphore-bounded with a fail-fast acquire timeout), opaque server-side tokens (256-bit secrets stored as SHA-256), short access tokens, device-bound refresh rotation with reuse detection and a grace window, single-use WS connect tickets, instant revocation. Migration 0003 (access_tokens, ws_tickets). Rotation and ticket redemption use an atomic claim-first UPDATE so concurrent races serialize cleanly.
- Permission evaluator (PR #11): a 63-bit `Permissions` bitmask and a pure `evaluate()`: @everyone base, role union, ADMINISTRATOR bypass, then channel overwrites (@everyone, role tier deny-wins, member overwrite absolute). Store loading (create_role/assign_role/set_*_overwrite, permissions_in_channel/base_permissions/has_permission). Migration 0004 enforces a single @everyone role.
- Message endpoints (PR #12): authenticated + authorized REST send/list/edit (`POST`/`GET /channels/{id}/messages`, `PATCH .../{message_id}`), wiring the evaluator (view to read, view+send to post, authorship-or-manage to edit). Shared http `error`/`extract` modules. Send idempotency scoped to (channel, author) so a reused id cannot leak a foreign message.

- WebSocket envelope and fan-out (PR #13): `/ws` authenticated by a redeemed connect ticket in a hello frame with protocol negotiation, a typed JSON envelope, a broadcast hub with per-event authorization, backpressure close, a bounded write timeout, a connection cap, 4 KiB frame limits, and logout closing live sockets.
- Read state and bundled sync (PR #14): monotonic last-read seq with derived unread, and `POST /sync` taking per-scope cursors with per-scope, aggregate, and snapshot-gap caps. A nonexistent channel now grants no permissions, so channel existence is not observable.
- Account deletion (PR #15): purge personal data, anonymize authored content, tombstone and free the username, revoke sessions and close sockets, with the login-versus-delete race closed by a write-locked liveness check in `open_session`.

- First-run bootstrap and channel routes (PR #16): the first account to register claims the deployment, seeding @everyone, an admin role, and a general channel, plus GET/POST /channels. Found by deploying and discovering a fresh server could authenticate but not message.
- In-process rate limiting (PR #19): token buckets per (class, key) with sweeping and a hard ceiling, keyed by user when authenticated and peer address otherwise, over-budget callers get 429.

**Phase 1 is complete**, including the rate-limiting deliverable. Server 0.5.0 is released and deployed.

**Phase 2 (client shell and text messaging) is merged.** What landed, in order:
- Wire protocol documented and the Dart API client (PR #21). The schema had drifted to 2 of 15 endpoints; it now documents the real surface.
- Local store (PR #22): Drift, idempotent by message id and order-safe by seq, so live push and catch-up can interleave.
- App shell (PR #23): width-driven adaptive layout, sync that catches up before attaching the socket, optimistic sends.
- Devices, blocking, report intake (PR #24) and invites (PR #27) on the server.
- Settings, safety UI, GoRouter, true-black theme, golden matrix (PR #26).
- Onboarding with the three entry points, invite redemption, unread badges (PR #28).
- Key-storage seam, remappable shortcuts, permessage-deflate interop (PR #29).

**Phase 3 (push relay and notifications) is largely done, and proven on real hardware.**
A backgrounded iPhone running the TestFlight build received a content-free push on 2026-07-25, with the relay logging `delivered=1`.

What landed:
- Server push path (PR #30): device registration scoped to the caller's own session, a client-reported lifecycle signal, a sealed content-free envelope (X25519, carrying only version, kind, channel, message id and seq), and a relay client.
  `PushSender` is a two-state thing rather than an error path, since a LAN-only self-host has nowhere for a relay to reach it.
  Triggering reads the lifecycle report, never raw WebSocket presence, because iOS suspends a socket without closing it.
- Relay hardening (relay PR #1): dead-token pruning, a VoIP topic for calls, a bounded worker pool under a real deadline, a registration ceiling, and `SECURITY.md`/`CODEOWNERS`/`MAINTAINERS.md`.
- Visible alerts (relay PR #2): message and mention kinds send a fixed generic string rather than a silent `content-available` push, which displayed nothing at all without a Notification Service Extension.
- iOS client registration (PR #31) and session persistence (PR #32).
- Android push, sender names, and the cross-repo envelope contract test (PR #33, relay PR #3). The contract job checks out both repos and drives a server-generated fixture through the relay's real HTTP handler.
- The endpoints the frontend still needs (PR #36): 21 routes (message delete, FTS search, profiles and member list, self profile, channel rename/delete, roles, overwrites, admin password recovery, report triage), the openapi contract gate (`tests/openapi_contract.rs`), and three privilege fixes found by adversarial review.
- Android delivery (PR #38): upload keystore signing (verified signer in CI, never debug), a release job attaching apk + aab, and the Play Console app (see identifiers below). First AAB 0.1.0 (4) is on the internal testing track; no testers added yet by owner choice.
- Push reachability in onboarding (PR #39): `/version` reports `push_enabled`, and the sign-in screen (where all onboarding paths land) probes it and shows a non-blocking notice when a server explicitly cannot push. Also fixed the sign-in field hardcoding a LAN address over the onboarding choice.

Still open in Phase 3:
- The iOS Notification Service Extension, which is what would replace "New message" with the decrypted content. It needs a new Xcode target. **That is no longer the blocker it reads as**: the broadcast upload extension landed on 2026-07-28 as a second target created by editing `project.pbxproj` as text, and CI compiles and links it, so the same route is open here.
- The Android half of the exit criterion: a real backgrounded Android device receiving a content-free wake. No Android hardware has been available; the pipeline, registration path, and contract test are done.

Known residuals, deliberately shipped:
- The session write lands just after the in-memory token becomes authoritative, so a process death in that window replays a spent refresh token into reuse detection and forces a sign-out. Recoverable, but closing it means reordering `SlimmApi`'s refresh path.
- The delete-account error path reports its failure but still strands the user.
- ~~Malformed query strings and JSON bodies still return axum's default error rather than the uniform JSON error contract.~~ Fixed 2026-07-28: `http::extract::{Json, Query, Bytes}` now wrap axum's own extractors and map their rejections to `ApiError`.
- `revoke_device` does not itself publish `SessionRevoked`, and that is the layering rather than a gap: the handler holds the hub, so `DELETE /devices/{id}` publishes for every session the removal revoked. Read twice as an open bug before somebody checked. Covered by a test since 2026-07-28 that also asserts a *second* device's socket survives, so a revocation that fanned out to the whole account would fail rather than look correct.
- `packaging/flatpak/*.yaml` and `packaging/rpm/*.spec` still do not exist, so a tagged release warns and skips both Linux artifacts. Phase 0's exit criterion names them and Phase 9 owns them properly. Deliberately not guessed at here: an untested manifest that merely looks right is worse than an honest skip, because it produces a broken artifact instead of a visible gap.

## Push credentials and identifiers

Bundle id `top.npcserver.slimm` on both platforms, following the existing `top.npcserver.checkin` convention.
A hyphenated form is legal on iOS but not in an Android `applicationId`, which is why the obvious `top.npc-server.slimm` was rejected.
The bundle id is deliberately not tied to the product name: the App Store display name is a separate field and stays free to change.

- Apple team `76S78SUWVM`, APNs key `AY9T3ZH9JX` (team scoped, sandbox and production; both settings are fixed at creation).
- App Store Connect app id `6794496135`, distribution certificate expiring 2027-07-25, profile `slim-m App Store Distribution`.
- Firebase project `slim-m` on the free Spark plan, FCM v1 enabled. Analytics and Gemini were declined at creation: neither is needed to send a push and both widen what Google sees of a messaging product.
- Play Console: app "slim-m", package `top.npcserver.slimm`, app id `4975488981113040762`, under the "Echo Messenger" developer account (`8924129173175438446`). Play App Signing is on; our keystore is the upload key only.
- Android upload keystore: `~/.secrets/slim-m/android-upload-keystore.jks` (alias `upload`, password alongside in `android-upload-keystore-password.txt`). GitHub secrets `ANDROID_UPLOAD_KEYSTORE_B64`, `ANDROID_KEY_PROPERTIES`, `ANDROID_GOOGLE_SERVICES_JSON` feed the release job.
- Secrets live in `~/.secrets/slim-m/`, mode 600, outside the repo. GitHub secrets are set for the TestFlight and Android pipelines.
- `google-services.json` and `GoogleService-Info.plist` are gitignored on purpose. Google does not class them as secrets, but this repo is public and they carry an API key, so CI injects them like the signing assets. A contributor needs their own to build the mobile targets.

Both store pipelines work from a `client-v*` tag: a signed iOS build reaches the Internal Testers group on TestFlight (automatic distribution on), and a signed apk + aab land on the GitHub release.
The aab still goes to Play by hand (no upload API wired); the first one was uploaded 2026-07-25.
The iOS job needs `set-key-partition-list`, without which `codesign` hangs a headless runner waiting for permission.
Uploading a new Play build: Test and release > Internal testing > Create new release.
The build number is **no longer taken from pubspec**: both store builds pass `--build-number=${{ github.run_number }}`, so it is monotonic and cannot be reused.
That was not cosmetic. `pubspec` sat at `0.1.0+4` through four client tags, so every TestFlight upload after the first carried a build number App Store Connect had already seen.
altool uploads a duplicate happily and the rejection arrives later by email, so all four release runs went green while the iPhone never saw a new build.
The pubspec `+N` is now only a local-build default and does not need touching per release.

Known gaps left from Phase 2, deliberately, and worth picking up before Phase 3 leans on them:
- **The UI has been driven by a human only lightly.** The live instance holds real messages from the owner, so the primary flow has been exercised, but there is no record of a full sign-up-to-send pass written down.
- **Golden images are not committed.** The matrix asserts no overflow at any scale (machine-independent, runs everywhere); the pixel comparison is behind `SLIMM_GOLDENS` with no reference images, because images generated off-CI would never match the runner and would mean a permanently red build. Generate them once on the CI runner and enable the flag there.
- The shared message context menu (edit, delete, pin/unpin) is now built; see "Cross-origin access, moderation UI, and channel administration" above. Reactions UI, the quick switcher, and haptics are not. The server side of reactions exists (PUT/DELETE on `/messages/{id}/reactions/{emoji}`, summaries on list, a ReactionsChanged event). History pagination is not built either.
- The shortcut table exists but is not yet bound into the widget tree.

~~Open follow-up noted during reviews: malformed query and JSON bodies still return axum's default plain-text error rather than the uniform JSON error contract (low).~~ Fixed 2026-07-28.
`http::extract` now defines `Json`, `Query` and `Bytes` wrappers that behave exactly like axum's own (including as a response type, for `Json`) but map a rejection to `ApiError` instead: a syntax error or a missing field is a 400 naming what was wrong, an oversized body is a 413, and both keep the `{"error": ...}` shape and `application/json` content type every other response already had.
The message for a bad body is the parser's own explanation one `source()` layer in, which names a missing field or a syntax position without the request body or a Rust type path; everywhere else keeps a static string.
The three raw-`Bytes` upload routes (attachments, custom emoji, avatars) got the same fix, since an oversized upload hit the identical axum-default-plain-text problem one layer earlier than the JSON body case did.

## Running deployment (LAN test instance)

The push relay also runs on this host, at `npc_projects/slim-m-relay/`, published through Traefik at `https://slim-m-relay.npc-server.top`.
It holds both provider credentials, bind-mounted read-only at mode 640; the image runs as `nonroot` so `group_add: ["1000"]` is what lets it read them.
`RELAY_TRUST_PROXY=true` because Traefik terminates TLS in front: without it every caller shares one rate-limit bucket and one abusive server throttles everyone.

The public name is `slim.npc-server.top`, a subdomain under the `npc-server.top` wildcard like everything else on the box.
(An earlier note here misread it as a separate `slim-npc-server.top` registration, which does not exist.)


A pinned instance runs on the owner's homelab box, deployed 2026-07-24.

- Host `npc@10.0.0.100` (Ubuntu, Docker). Stack at `/home/npc/docker-server/npc_projects/slim-m/` (`docker-compose.yml` + `.env`), following that host's one-directory-per-stack convention.
- Image `ghcr.io/nc1107/slim-m-server:latest` (the release now publishes a rolling `latest` alongside the version and sha tags), SQLite on the named volume `slim-m_slimm_data`, reachable at `http://10.0.0.100:8095`.
- Auto-updates are on: the container carries `com.centurylinklabs.watchtower.enable=true`. That host runs **exactly one** Watchtower, `scw-watchtower` in `npc_projects/scw_server/`, in label mode across every stack. Do NOT add a second Watchtower to this stack: a new instance stops the existing one on startup, which is how `scw-watchtower` briefly got killed on 2026-07-24 before being restored.
- Published at **`https://slim.npc-server.top`** through Traefik since 2026-07-25 (joined `traefik_proxy`, labels mirror the relay stack's), and still reachable on the LAN at `http://10.0.0.100:8095`.
- Verified live against 0.5.0 (auto-updated from 0.4.0 by Watchtower with no manual step, proving the pipeline): `/healthz`, `/version`, a 13-check auth and WebSocket smoke run (including a real ws hello handshake and post-deletion refusal), and a 17-check messaging run (bootstrap seeding, send, idempotent retry, list, edit, read state, sync, and the member-versus-admin permission split), plus rate limiting confirmed live (5 answered, then 429).
- Operate it with `docker compose` from that directory. It tracks `latest`; set `SLIMM_VERSION` in `.env` to a version to freeze it.

### The SFU on that box (added 2026-07-26)

`slim-m-livekit` runs in the same stack, published through Traefik at `https://livekit.npc-server.top`, and the server is pointed at it with `SLIMM_LIVEKIT_URL=wss://livekit.npc-server.top`.
Both services read one `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` pair out of the stack's `.env`, so they cannot drift apart.
Verified end to end: a token signed the way `voice.rs` signs one validates against the SFU both through Traefik and directly on the compose network, and a tampered signature comes back 401.

Its ports are **not** the defaults, because three things on that host already held them.

- TCP fallback on **7891**, not 7881: `echo-messenger-livekit-1` has 7881.
- ICE media on **50300-50400/udp**, not 50000-50100: that same container has 50000-50200.
- TURN is **disabled**. UniFi holds 3478, and a TURN relay on a non-standard port reaches nothing the published ICE range does not already reach, so it was only ever going to advertise candidates that time out. A network that blocks the ICE range blocks 3479 too; the answer for one of those is TURN/TLS on 443, which is a Traefik TCP passthrough rather than a UDP port.

Two failures cost real time here and are worth knowing before touching this again.

- **The server reporting `voice enabled` says nothing about the SFU being up.** It is the server's opinion of its own config. LiveKit crashlooped behind a perfectly healthy `voice enabled` line for half an hour. `compose-smoke` now checks the SFU separately, and that gap is why.
- **LiveKit exits if it cannot resolve a STUN hostname**, which it needs to discover the address peers must reach it on. That box runs systemd-resolved, so the container inherited a `127.0.0.53` stub that does not exist inside it. The service carries an explicit `dns:` block for this, in prod and in the example compose.

Note that `livekit.npc-server.top` is proxied by Cloudflare, which rejects some non-browser user agents with `error code: 1010` - `Python-urllib` gets a 403 there while curl and the Dart client do not. Worth remembering when a probe against that name fails in a way the SFU could not have caused.

## Repository layout

```
crates/slimm-server   Rust home server (Axum + embedded SQLite via sqlx). A lib (slimm_server) plus a thin bin.
  src/                lib.rs, main.rs, config.rs, db.rs, http.rs, ids.rs, store.rs
  migrations/         forward-only sqlx migrations (0001 init, 0002 core schema)
  benches/            criterion hot-path benchmarks
  tests/              integration tests
schema/               openapi.yaml, the single source of record for the wire protocol
client/               Flutter client, a Dart native pub workspace (packages/api, design_system, data, platform, rtc, voice_canvas, app)
docker/               server.Dockerfile (multi-stage musl + distroless)
deploy/               docker-compose self-host example (server + Caddy + LiveKit + Litestream), Caddyfile, .env.example
perf/                 performance baseline model
.sqlx/                committed sqlx query cache (offline builds); regenerate after query changes
docs/                 brief, strategy, roadmap, decisions, research, design
```

## Architecture summary

- Server: Rust + Axum serving HTTP and WebSocket in one process. Embedded SQLite in WAL mode via sqlx, single serialized writer plus a read pool, all reachable to become a repository trait when Postgres is actually needed. Postgres is a documented later swap.
- Identity and ordering are two separate columns. Identity is a client-generatable UUIDv7. Order is a per-(channel, stream) monotonic `Seq`, allocated in the same transaction as the insert. Snowflake ids were rejected (single-writer needs no worker-id coordination).
- Durable writes go over idempotent REST keyed by UUIDv7; the WebSocket carries server-to-client fan-out plus ephemeral signals only.
- Wire format is schema-first JSON generated from OpenAPI plus JSON Schema, additive-only, with permessage-deflate.
- Media is self-hosted LiveKit (Opus plus VP8 simulcast). The Voice Canvas uses a per-object model with a snowflake-free per-scope op sequence.
- Security is transport-only in v1 (TLS 1.3, server holds plaintext); per-user and per-device keys are pre-wired for later opt-in E2EE DMs. Opaque session tokens (Argon2id), per-device push keys.
- Push relay is a separate stateless Go forwarder: APNs plus FCM, content-free encrypted payloads, and each device token bound to the key that registered it.

Decisions of record: [0001](docs/decisions/0001-owner-decisions.md) (owner product decisions), [0002](docs/decisions/0002-architecture-followups.md) (SQLite, same-deployment DMs, presence opt-out), [0003](docs/decisions/0003-library-decisions.md) (library choices, and a corrected Linux-media finding).

## Owner decisions to honor

Transport-only encryption in v1 (E2EE later, keys pre-wired).
The Voice Canvas is a large bounded world, not literally infinite.
No automated content or media scanning; safety is manual reporting plus report/block/moderation tooling. Target use is small self-hosted friend groups.
One backend deployment is one community. Direct messages work only between users on the same deployment in v1.
Read receipts to other users are deferred; presence has a hide/appear-offline option.
Self-hosted account recovery is an admin-issued one-time reset code (no email).
The official instance is single-process with state behind a swappable interface.
A designer review precedes design-token lock. The accent is glacier cyan (`#1B6F91` light, `#58B4D8` dark, decided 2026-07-27; teal until then), on a neutral cool-slate palette, IBM Plex Sans, border-first elevation, flat grouped messages.
The UI uses Lucide icons and never emoji as chrome. Emoji are user content (reactions) only.
Join and leave sounds default off above roughly 8 participants. The official instance publishes no moderation SLA.

## Local development

Toolchains present in this environment: cargo/rustc 1.94, go 1.26, docker, node, gh (authenticated as NC1107).
Flutter 3.44.8 stable (Dart 3.12.2) is installed at `~/development/flutter`, on PATH via `.zshrc` and `.bashrc`. `flutter doctor` reports no issues.
The host is Fedora 44 **KDE Plasma** on Wayland with an NVIDIA GPU, and the Android SDK is present with licences accepted, so Linux desktop and Android can both be built and run locally.
Android needs a JDK, and the system only ships a JRE (Fedora 44 packages no LTS `-devel` JDK, and `javac` is absent), so the first Android build fails with "does not provide the required capabilities: [JAVA_COMPILER]".
A user-local Temurin 21 at `~/.local/jdk/jdk-21.0.12+8` fixes it without root, wired in with `flutter config --jdk-dir=...`.
JDK 21 rather than the packaged 25 because that is the LTS the Android Gradle Plugin actually supports.
Two things still cannot be verified here:
- **iOS** needs macOS and Xcode, so it stays CI and TestFlight only (and that job still needs the Apple secrets).
- **Golden files** are sensitive to the engine build and font rendering, and CI generates and checks them on `ubuntu-latest` / `stable`. Run goldens locally to see failures, but regenerate them only in CI, or local and CI renders will disagree.
Fedora KDE Plasma Wayland is the Linux development and test target (owner decision, 2026-07-26), which is what this box runs. The roadmap used to name GNOME; that was corrected rather than the environment. The product still ships cross-platform, so other desktops are release targets, just not where the work is validated day to day.
`sqlx-cli` 0.8 is installed at `~/.cargo/bin`.

Everyday commands:

```bash
# Run the server
cp .env.example .env
cargo run --bin slimm-server
curl localhost:8080/healthz          # -> ok
curl localhost:8080/version          # -> {"name":"slim-m",...}

# Offline build/test (uses the committed .sqlx cache, no database)
SQLX_OFFLINE=true cargo fmt --all --check
SQLX_OFFLINE=true cargo clippy --all-targets --all-features -- -D warnings
SQLX_OFFLINE=true cargo test --all

# Container image (builds offline)
docker build -f docker/server.Dockerfile -t slimm-server:dev .

# Client (Dart pub workspace; mirrors what client-ci runs)
cd client
flutter pub get
dart analyze
dart format --output=none --set-exit-if-changed .
(cd packages/design_system && flutter test)   # tests live per package, not at the root
```

sqlx query workflow (IMPORTANT): the `query!` and `query_as!` macros are compile-time checked.
After adding or changing any macro query you MUST regenerate the offline cache, or CI and the Docker build (which run with `SQLX_OFFLINE=true`) will fail:

```bash
export DATABASE_URL="sqlite:////tmp/slimm-dev.db"     # four slashes = absolute path
( cd crates/slimm-server && sqlx database create && sqlx migrate run --source migrations )
cargo build                                            # checks queries against the db
cargo sqlx prepare --workspace                         # writes .sqlx/, commit it
```

Test databases are temp SQLite files (`Config { port, database_path }` then `db::connect`); do not use `:memory:` with the multi-connection pool.

**They used to leak, and on this box that was not cosmetic.**
96 sites across 46 test files built a path under `std::env::temp_dir()` and nothing ever deleted it, so a full `cargo test --all` left roughly a thousand `slimm-*.db` files behind, plus their `-wal` and `-shm` companions.
`/tmp` here is a 16GB tmpfs shared with every other tool, and on 2026-07-28 the accumulation reached 20,000 files and filled it, which surfaces as the shell failing every command that writes to stdout with `disk quota exceeded` rather than as anything mentioning tests.
Clear a pre-fix mess with `find /tmp -maxdepth 1 -name 'slimm-*' -delete` (non-empty leftover media directories need `-exec rm -rf {} +` instead).

**Fixed, 2026-07-28.**
`tests/support/mod.rs` is a `TestDbGuard`, included per test binary with `mod support;` (a plain top-level file) or `#[path = "../support/mod.rs"] mod support;` (a `tests/<name>/main.rs` subdirectory binary), since integration tests are separate crates and a `mod.rs` with no `main.rs` is never auto-discovered as its own target.
It deletes its `.db`, `-wal` and `-shm` siblings on drop, panic or not, and every one of the 46 files now threads it through: a helper returns `(Store, TestDbGuard)` (or `(SqlitePool, TestDbGuard)`), and every wrapper around that helper has to carry the guard onward too, or it drops (and deletes the database) the moment the wrapper returns, before the test body ever runs.
That exact bug hit three wrappers first (`invites.rs`'s `fixture`, `registration_gate.rs`'s `claimed`, `read_state_sync.rs`'s `setup`) and surfaced as "no such table", not as a leak.
Left unconverted: `tests/response_contract/**` (a concurrent change owned it) and four sites that create a temp media directory rather than a database (`emoji_refusal.rs`, `attachments/fixtures.rs`, `emoji_import/fixtures.rs` twice) - a different leak shape, no `-wal`/`-shm`, and out of scope for this guard.

## Contribution conventions

- Branch, then PR, then squash-merge to main. release-please plus conventional-commit PR titles.
  **The PR title is the only thing release-please reads**, because squashing throws the individual commits away and keeps them as bullets in the body, which it does not parse. A title without a `feat:`/`fix:` prefix produces a release whose changelog silently omits everything in that PR; client 0.8.0 shipped that way (#117) and the omission was only caught by reading the release PR afterwards. Hand-editing `CHANGELOG.md` to patch it is not the fix, since that file is generated.
- Commit with `git commit -s` (DCO sign-off). NEVER add an AI attribution or co-author trailer to anything.
- Never use the em dash character; use a plain dash. In long Markdown files, put each full sentence on its own physical line.
- No emoji as interface chrome (a CI gate enforces this); use Lucide icons. SPDX headers on every source file (a CI gate checks the Rust ones).
- **Files: 300 lines soft, 500 hard.** 300 is the review budget, and a file over it should be split before it grows again.
  500 is a ceiling rather than a budget: a file past it does not get reviewed properly, so split it in the change that would cross the line.
  Generated code is excluded (`*.g.dart`, `*.freezed.dart`, `.sqlx/`, generated protobuf), because its size is not a human's decision.
- **Functions: 7 parameters.** This is not an invented number.
  Clippy's `too_many_arguments` fires at 8 and SonarQube's equivalent rule is also 7, so both linters already in this stack enforce it for free.
  Dart **named** parameters on a widget or data-class constructor are exempt: a Flutter widget legitimately takes many, and a named argument is self-describing at the call site in a way a positional one is not.
  Past 7 positional parameters, the fix is a struct or a parameter object, not a longer signature.
- **No comment may exceed one line.** Owner decision, 2026-07-27, tightened from two: the code was carrying more comment than code.
  Code explains how; a comment explains why, and one line is enough for a why.
  If the reason genuinely needs more room it belongs in a doc comment on the item, in `docs/`, or in the decision record - not in a block above a statement.
  A long comment above a confusing function is a sign the function should be refactored, which is the rule this one exists to enforce.
  **Scope:** the cap is on plain comments (`//`, `#`) only.
  Doc comments (`///`, `//!`, `/**`) are exempt, because they carry an item's contract to its callers and to `cargo doc` / `dart doc`, which is a different job from explaining a line.
  They are not a loophole: a doc comment is for the contract, and one that has grown past roughly ten lines is reference material that belongs in `docs/` with the doc comment linking to it.
  Test files are in scope. A long comment there is usually a why worth keeping, so shorten it or move it to a doc comment on the test rather than deleting the reasoning.
  **One exemption, for languages with no doc-comment syntax.** In YAML, TOML and shell, a `#` block at the very top of the file is that file's only documentation mechanism, so a file header there is treated as a doc comment and is exempt.
  A `#` block anywhere else in those files is an ordinary comment and capped at one line like everything else.
  The point of the rule is that reasoning should live somewhere durable and findable, not that reasoning should be deleted: when shortening, move the why to a doc comment or to `docs/`, never drop it.
- Anything published under the owner's name (PR titles and bodies, issues, review comments, releases) is written in Nick's voice: read `~/.claude/Voice.md`. It is plain, hedged, anti-hype, lowercase product names, no emoji or exclamation points, and it walks through how a thing works. Commit messages, code, and working conversation stay in the normal clear register.
- Subagent model selection (from the owner's global instructions): haiku for trivial ops, sonnet for default coding and analysis, opus only for orchestration or hard reasoning; never use fable for engineering. Prefer sonnet-4-6 over sonnet-5. Workflow/Agent tooling only accepts tier aliases (haiku/sonnet/opus/fable), so full model ids cannot be passed there.
- schema/openapi.yaml is gated against the router: `crates/slimm-server/tests/openapi_contract.rs` parses the routes axum actually serves out of `src/http.rs`/`src/http/*.rs` and the paths documented under `paths:` in the schema, and fails `cargo test` (locally and in CI, via server-ci, no separate workflow to remember) if either side has something the other does not. This is why adding, removing, or renaming a route belongs in the same change as the matching edit to `schema/openapi.yaml`: the build will not pass otherwise, and the failure names the exact method, path, and file that drifted.

## CI and release, plus gotchas learned the hard way

Workflows: server-ci, client-ci, schema-ci, hygiene, perf, release. All green on main.

- Multi-arch images are built NATIVELY per architecture (ubuntu-latest for amd64, ubuntu-24.04-arm for arm64), pushed by digest, then merged into one manifest and cosign keyless-signed. No QEMU, no `cross`. The static binaries are built the same native-per-arch way. `cross` was dropped because its arm64 toolchain image hit a GLIBC mismatch.
- The Dockerfile builds natively for whatever platform buildx targets; do not reintroduce `--platform=$BUILDPLATFORM` cross-copying (it silently ships a host-arch binary in the foreign-arch image).
- `sigstore/cosign-installer` has no moving `v4` tag; pin it to an exact version (currently `@v4.1.2`). The docker/* actions do publish moving major tags, so `@v4`/`@v7` are fine there.
- Publish jobs gate on `(release-please success && released) || startsWith(github.ref, 'refs/tags/server-v')`, and server-image-merge has an explicit `if`, so re-pushing a tag can re-publish.
- `SQLX_OFFLINE: "true"` is set at the top of server-ci and perf, and in the Dockerfile builder; the `.sqlx/` cache is committed.
- release-please keeps a STANDING release PR open per component by design; it is the release button, not review work, and reopens after each affecting merge.
  **The client is registered again as of 2026-07-27**, tracked at `client/` with the version in `client/pubspec.yaml`, and the manifest seeded to 0.2.3 so it continues from the last hand-cut tag rather than proposing 1.0.0. It was pulled during Phase 1 "until it has real content" and that note outlived its reason by several phases, which is why every client release since had to be tagged by hand.
  The pipeline never stopped expecting it: `release.yml` already read `client--release_created`, `client--tag_name` and `client--version`, and only the `packages` entry was missing.
  A client release is now the same two steps as a server one: merge the work, then merge the `chore(main): release client X.Y.Z` PR it opens. That second merge is what tags `client-vX.Y.Z` and builds the TestFlight and Play artifacts. Hand-tagging still works, since the jobs keep their `refs/tags/client-v` branch.
- `dart format` is strict (tall style, Flutter 3.44.x). Write short unambiguous lines; the client cannot be formatted or analyzed locally here, so CI is the check.

Environment note: the Claude Code auto-mode classifier blocks creating GitHub repositories and some repo-settings changes; the owner must do those (or grant `Bash(gh:*)`). Plain `git push` works.
The "Allow GitHub Actions to create and approve pull requests" repo setting was enabled so release-please can open PRs (`gh api -X PUT repos/NC1107/slim-m/actions/permissions/workflow -F can_approve_pull_request_reviews=true -f default_workflow_permissions=write`).

## Open items that need the owner

- **Deploy the invite gate.** The live instance at `https://slim.npc-server.top` still accepts anonymous registration and will until it runs a build containing the gate. Watchtower tracks `latest`, so cutting a release is what closes it; nothing else needs doing on the host.
- **Watch the next release PR.** `release-please-config.json` gained the `cargo-workspace` plugin so a version bump also updates `Cargo.lock`, which the new `--locked` builds require. That is the one change in the audit pass that could not be verified locally, and its failure mode is a red release PR, not a bad release.
- **`bump-minor-pre-major` is why the server stays on 0.x.** PR #42 landed as `feat!` (registration genuinely changed behaviour for a claimed deployment), and release-please read the breaking marker on a 0.x project as "go to 1.0.0" and opened exactly that PR. It was closed unmerged. The flag makes a breaking change bump the minor while under 1.0, so that reads 0.9.0 instead. 1.0 is a Phase 9 deliverable and the product is not even named yet (owner decision 9), so nothing should reach it by accident.
- **Adding Play internal testers needs the owner.** There is no Play Developer API credential anywhere: `~/.secrets/slim-m/` holds only the Firebase/FCM service account, which is scoped to messaging and cannot touch Play. Tester lists live in Play Console > Test and release > Testing > Internal testing > Testers, and each tester must then accept the opt-in link before the build appears for them.
- A real Android device test of the push path end-to-end (the last Phase 3 exit criterion with any work left).
- Reviewer protection on the `release` and `testflight` GitHub Environments (they exist but are ungated).
- Flatpak and rpm packaging manifests (`packaging/flatpak/*.yaml`, `packaging/rpm/*.spec`); the release jobs warn-and-skip until they exist.
- Optional GPG signing secret for the Linux client checksums.
- A decision on whether to keep release-please's auto-PR flow or switch to manual tag-based releases (to keep the repo at zero open PRs).
- ~~Where rendered API docs should live.~~ Settled 2026-07-26: nowhere. GitLab renders an OpenAPI file in its repo browser the way GitHub renders a README, GitHub has no equivalent, and building redoc HTML into a run artifact nobody downloads is not worth a job. The render step is gone; `redocly lint` stays, since that is the schema-ci gate. `schema/openapi.yaml` is read as the source. If a browsable copy is ever wanted: `npx @redocly/cli build-docs schema/openapi.yaml -o /tmp/api.html`.
- Linux desktop screen sharing on Wayland was written up as a blocking `flutter_webrtc` bug (issue 1542, the PipeWire/xdg-desktop-portal path not waiting for the picker response). **The owner reports getting screen share working in their own testing**, so that research finding looks stale or GNOME-specific rather than a Wayland-wide block. Treat it as probably fine and confirm in the Phase 4 spike rather than planning around a fallback. If it does break, the fallbacks are a newer flutter_webrtc, contributing the portal fix, or an X11 session.

## Parked and reference

- [docs/BACKLOG.md](docs/BACKLOG.md): accepted extra features, architectural hooks to preserve, and deliberate declines from the segment gap analysis.
- [docs/design/design-language.md](docs/design/design-language.md): the visual identity spec (colour, type, spacing, iconography, motion). It moved out of `docs/research/` on 2026-07-26, which is where it was hiding.
- [docs/decisions/0004-visual-identity-review.md](docs/decisions/0004-visual-identity-review.md): the designer review that gated token lock. Read this before changing a token; it also closes the seven accent roles and settles the canvas `window` contradiction.
- [docs/design/layout-explorations.md](docs/design/layout-explorations.md): the parked Spaces/Focus/Deck layout concepts (the sidebar layout was kept for v1, and the review confirms nothing needs reopening).
- [docs/design/feature-exploration.md](docs/design/feature-exploration.md): the segment feature-gap analysis.
- [docs/research/](docs/research/): the specialist domain reports and adversarial reviews that fed the strategy; note that `stack-decision.md` and the fresh domain files supersede any older content.
- Interactive design mockups were published as Claude artifacts (a design proposal and a layout-explorations page).
