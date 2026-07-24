# Flutter Client Plan: Adversarial Review

Target document: `docs/research/flutter-client.md`.
Cross-checked against `docs/BRIEF.md`, `docs/decisions/0001-owner-decisions.md`, and `docs/research/stack-decision.md`.

Method note: this review is derived independently from the brief, the owner decisions, and the decided stack, plus platform behavior that is independently verifiable (Apple's PushKit and CallKit contracts, the Wayland and xdg-desktop-portal screen-capture model, GNOME Shell's tray removal, Drift's documented stream-invalidation model, Flutter's engine and image-cache defaults).
Per the review brief, echo-messenger is off-limits as a reference or rationale everywhere in this document, including the Voice Canvas region, because this review does not touch Voice Canvas internals at all.
Nothing below cites a prior project's choice as a reason for anything; every finding names a specific line of reasoning from the brief, the owner decisions, the stack decision, or verifiable platform fact.

Severity key: critical findings would force a redesign of the plan as written.
Major findings are real defects that should block sign-off until addressed.
Moderate findings are real costs or gaps that do not block the overall direction but should be resolved before implementation starts.
Minor findings are worth fixing but low risk either way.

## Critical findings

### 1. Report, block, and the pre-connect capability handshake have no owner anywhere in the plan

Owner decision 3 is explicit and specific: the client verifies, via a capability handshake, that a server exposes report and block *before connecting*, precisely because a third-party fork could strip moderation while the official app remains the access point.
`flutter-client.md` names five packages and describes what each owns down to the level of "auth-refresh and reconnect-backoff need hand control" inside `api`, yet never once mentions report, block, moderation screens, account deletion, or the capability handshake itself.
This is not a missing screen that can be bolted onto `app` later.
A pre-connect capability check has to live inside the connection bootstrap sequence that `api` already claims sole ownership of and already describes as needing hand-written control flow, which means the handshake changes the shape of the one piece of client logic this document is most specific about, not an item the current design has room for as an afterthought.
Discovering this gap after `api`'s connect/auth/reconnect state machine is built and tested means reopening exactly the code this document singles out as needing the most custom care.
Fix: state where the capability handshake sits in the connection lifecycle (before or interleaved with auth), which package owns report/block/delete-account screens, and add it to the testing pyramid now, not after the package boundaries are already load-bearing.

### 2. Linux screen capture has no owner anywhere in the platform integration plan

The brief lists screen sharing as core functionality for both group chats and direct messages, and names Fedora GNOME Wayland as the primary Linux test environment.
On Wayland there is no direct capture API a client can call; screen and window capture goes through the `org.freedesktop.portal.ScreenCast` portal, which negotiates a PipeWire stream after a compositor-drawn consent picker, a fundamentally different integration surface from anything a browser-style permission prompt on iOS or Android resembles.
`flutter-client.md`'s platform integration section names exactly four abstraction categories: notifications, secure storage, window management, call integration.
Screen capture is not one of them, and it is not mentioned under any other package either: not `data`, not `api`, not the reserved `voice_canvas` boundary, which is explicitly scoped to drawing and rendering, not capture permission flows.
A working Linux screen-share needs a portal-consent UI, PipeWire stream lifecycle management (start, revoke-on-portal-session-end, source picker for monitor versus window), and hand-off to the WebRTC capturer, and none of that has a package to live in as written.
Concrete failure mode: whoever implements screen share first has to invent a new integration point mid-implementation, most likely widening `platform`'s scope after the fact in a way the document's own "small abstract interfaces" framing was supposed to prevent, or worse, ships an iOS/Android-first screen share that silently does nothing useful on the brief's own named primary desktop platform because nobody budgeted for the portal flow.
Fix: name screen capture as a fifth `platform` integration category now, with an explicit note that its Linux implementation is portal- and PipeWire-based and its consent UI is compositor-drawn, not something the app controls the look of.

### 3. iOS PushKit and CallKit's synchronous native requirement is understated as ordinary Dart-interface platform integration

`flutter-client.md` covers this in one line: "iOS gets CallKit and PushKit integration for cold-launch VoIP wake from the relay, and Keychain-backed storage," filed alongside secure storage under the same "small abstract interfaces with per-OS implementations" pattern the whole platform package is built on.
That pattern implies a Dart-facing interface with a plugin-style per-OS backing implementation, reachable through the same provider graph as everything else.
It does not hold for this one integration point, and the reason is structural, not a matter of more careful implementation.
On a cold launch (app fully terminated), iOS delivers the incoming VoIP push to a native `PKPushRegistryDelegate` callback before there is any guarantee the Flutter engine or a Dart isolate has started, and Apple requires that callback to report the call to CallKit synchronously, in that same native callback, not after some later async handoff.
An app that fails to report a VoIP push to CallKit gets terminated by the system, and repeated failures put the PushKit entitlement itself at risk, so getting the ordering wrong is a store-compliance risk, not just a missed call.
A "small abstract interface, per-OS implementation" framing invites an implementer to route this through the same Dart-callable plugin pattern as Keychain access, where the natural instinct is to marshal into Dart and let application logic decide what to do, which is exactly the extra hop that breaks the synchronous, pre-Flutter-engine contract.
Fix: document this integration point as a named exception to the platform package's general pattern, with an explicit minimal native Swift AppDelegate/PushKit delegate that reports to CallKit before touching the Flutter engine, and put a regression test on the report-then-launch ordering, not a code review comment.

## Major findings

### 4. LiveKit's stateful connection lifecycle is folded into an OS-abstraction package with no testability seam

`platform` is described as holding "notifications, secure storage, window management, call integration," a set otherwise made up of thin, mostly stateless OS-facing interfaces.
"Call integration" is the odd one out: a LiveKit client wrapper is not a thin OS interface, it is a stateful subsystem managing connection lifecycle, mic/camera/deafen state, active-speaker tracking, reconnect and rejoin handling, and CallKit bridging, all with real internal state machines and real races (join-during-leave, rejoin-after-drop).
Putting that inside the same package as "read a value from Keychain" mixes a thin OS shim with a large, third-party-SDK-shaped subsystem under one boundary, which works against the document's own stated reason for having packages at all: a compiler-enforced public API per concern.
The testing pyramid section never mentions voice, LiveKit, or any injection seam for testing connection state without a live SFU, which is a direct consequence of not giving this subsystem its own named package and public API: a boundary that does not exist cannot be designed to be testable.
Concrete failure mode: the highest-complexity, highest-race-risk subsystem in the client ships with the same test rigor as a Keychain wrapper, because nothing in the plan forces its public API to expose an injectable connection point.
Fix: give call/voice state its own package (or an explicitly named module inside `platform` with its own public API and its own test seam), and add "connection state is testable without a live SFU" as a stated design constraint before implementation starts.

### 5. The `data` package's public API never defines a non-reactive read primitive, so the off-Riverpod hot-path rule has no boundary to enforce it at

The startup and rendering section states a clear general principle: any high-frequency UI stream, not just canvas, must bypass the wide provider tree through a narrow `ChangeNotifier`/`ValueListenable` island, never a `StreamProvider`.
The offline-storage section, in the same document, describes exactly one read pattern for `data`: reactive `Stream` queries, described as the thing repositories expose.
No snapshot, one-shot, or synchronous read method is named anywhere in `data`'s described public surface.
That leaves a real gap: the one package in scope in this document, the one whose public API this document is actually responsible for fixing, never commits to exposing anything other than the exact primitive the hot-path rule says high-frequency consumers must not use directly.
A future high-frequency consumer, canvas or otherwise, inherits an ambiguous contract from a fully-specified package, and the general principle in the rendering section has no teeth against it: there is no lint, no architecture test, and no `data` API shape described that would stop someone from wiring a `StreamProvider` straight to a `data` query for a frequently-updating surface, which is precisely the anti-pattern the same document warns against one section later.
Fix: `data`'s public API section should name both a reactive `Stream` surface for normal UI and an explicit synchronous/snapshot read method intended for hydrating external hot-path state, and the hot-path rule should be backed by something checkable (a lint rule, an import-boundary test) rather than a paragraph of prose.

### 6. Impeller is declared required with no fallback for the platform and workload most exposed to its immaturity

`flutter-client.md` states Impeller is required and that its enabled state is "verified per platform in CI rather than assumed, since its maturity differs between iOS and Linux."
That sentence acknowledges the risk and stops there.
Impeller's rollout has consistently prioritized iOS and Android ahead of the Linux desktop embedding target, and the workload this document spends the most words budgeting for, a `CustomPaint`-heavy, multi-layer, high-frequency canvas, is exactly the workload most exposed to a renderer that is less mature on one of the two named primary platforms.
"Required" with a CI check that only confirms the flag is set says nothing about what happens if Impeller-on-Linux is measurably worse for this workload at implementation time: no fallback rendering path, no acceptance threshold that would trigger a fallback decision, no statement of what Flutter/Linux Impeller status was actually true when this requirement was written.
Concrete failure mode: the team hits a real frame-time regression on Fedora mid-implementation, discovers "required" was aspirational rather than validated, and has no documented decision process for what to do next, on the platform the brief names as a primary test target.
Fix: name the acceptance criteria (a concrete frame-time or dropped-frame budget on the actual Linux CustomPaint workload) that would trigger a Skia fallback decision, and record what Linux Impeller status was checked when "required" was written.

### 7. The testing pyramid has no coverage plan for voice, screen share, or any performance or battery regression, despite both being explicit brief priorities

The brief lists voice calls and screen sharing as core functionality for both group chats and direct messages, and separately names memory, CPU, network, battery, cold and warm startup, UI responsiveness, and animation smoothness as first-class, continuously-evaluated metrics, not one-time checks.
The testing pyramid section names exactly three integration flows: invite-based account creation, send and receive a message, reconnect-and-resync.
Voice call join, leave, and reconnect and screen share do not appear anywhere in the testing section, despite `platform`'s "call integration" being named as an owned responsibility earlier in the same document.
Nor does any form of automated performance regression testing appear: no frame-timing budget check, no cold/warm start time assertion, no memory-growth check, no battery-drain benchmark, anywhere in the pyramid.
A "constantly evaluate" requirement that has zero automated enforcement in the one document responsible for the client's test strategy means these metrics are evaluated only when someone remembers to look, which is precisely the failure mode "first-class feature" language is meant to prevent.
Fix: add voice join/leave/reconnect and a basic screen-share smoke flow to the integration test list, and add at least one CI-gated performance signal (a `flutter drive` timeline-summary budget for cold start and a canvas or list-scroll frame-time budget) so a regression fails a build instead of surfacing as a user complaint.

### 8. Three code generators and a six-package workspace exist before a single feature ships, with no unified regeneration workflow described

The plan commits to `build_runner`-driven Riverpod codegen, a separate `build_runner`-driven Drift codegen, and a third, non-`build_runner` schema-first Dart codegen pipeline generating types from the OpenAPI/JSON Schema source of record, spread across five packages plus a reserved sixth.
A Dart pub workspace resolves dependencies across packages; it does not orchestrate `build_runner` runs across them, so each package with generated code needs its own generator invocation, and the schema codegen is a wholly different tool with its own invocation and configuration, not a `build_runner` builder at all.
The plan's own risk notes acknowledge "`build_runner` adds a build step and occasionally opaque errors" and that "Drift's codegen stacks with Riverpod's," but both are treated as one qualitative risk, when in practice a contributor touching `api` after a schema change has to know about, and correctly sequence, two unrelated codegen mechanisms across package boundaries, not one.
No single documented command (a script, a Makefile target, a `dart run` entry point) is named that regenerates everything in the correct order, which is exactly the kind of friction the brief's "easy to contribute to" goal is meant to rule out.
Fix: name one top-level regeneration command now, before the package count or generator count grows further, and treat "delete `.dart_tool`, retry" contributor friction as a cost to budget explicitly rather than a footnote.

### 9. Drift's table-level stream invalidation is never addressed, so idle CPU cost scales with the number of live queries, not the rate of relevant change

Drift's reactive `Stream` queries recompute on any write to a table the query reads from, by default, because dependency tracking is table-level, not row-level.
A sidebar with live per-channel unread-count streams, a live message stream for the open channel, and any other per-channel reactive query all watching the `messages` table will each re-run on every message insert into any channel that table serves, not only the channel the write actually touched.
`flutter-client.md` names Drift as giving "reactive `Stream` queries" as a headline benefit and never once discusses scoping or batching that invalidation, which is a real cost against the brief's own "efficient database queries" and "low idle CPU usage" goals, and against "low idle CPU" is one of the two axes the whole server-side stack decision was built around; the client should not casually reintroduce the same class of cost the server design worked hard to avoid.
Concrete failure mode: a user active in several channels sees CPU churn proportional to total server-wide message volume across all their open queries, not to the messages actually relevant to each query, which is invisible in a demo with one test channel and only shows up once real usage has several channels active at once.
Fix: state a query-scoping discipline now (narrower queries, manual `updates` stream scoping, or Drift's custom stream utilities to limit recomputation to relevant rows) rather than leaving Drift's default behavior as an implicit, unexamined choice.

### 10. Client-side message and attachment history has no retention, archival, or vacuum policy, unlike the server's explicit compaction plan

`data` is described as "the single source of truth for conversations, messages, channels, and settings," with every synced event upserted in by UUIDv7, and nothing in the plan describes what, if anything, ever leaves that local database.
The brief names low storage overhead and disk usage as first-class, continuously-tracked metrics, applying to the client exactly as much as the server.
A long-lived client on a years-old friend-group deployment accumulates the entire message and reaction history for every channel and DM it has ever synced, with no described pagination-aware pruning of old local history, no vacuum policy for the client's own SQLite file, and no cap distinct from the attachment cache's already-described bounded LRU.
This differs sharply from the server side of the same architecture, which explicitly plans keyset pagination, an op-log compaction job, and backup-window discipline for exactly this class of unbounded growth.
Concrete failure mode: a client used daily for a couple of years on an active server accumulates gigabytes of local history with no mechanism to reclaim space, on exactly the mobile platform (iOS) where uncontrolled app storage growth draws both user complaints and App Store scrutiny.
Fix: state a client-side retention policy (a rolling local window with re-fetch-on-scroll-back beyond it, or a periodic `VACUUM`/size cap with user-visible controls), mirroring the rigor already applied to the attachment cache and the server's own compaction plan.

### 11. No decoded-image memory budget is set for ordinary chat content, only for the out-of-scope canvas cache

The document's only stated memory discipline for decoded bitmaps belongs to the reserved canvas package, which is out of scope here.
Ordinary chat use, message attachments, pasted images in DMs and channels, and user avatars, all decode into memory through the same rendering pipeline and are not mentioned at all in this document's memory or performance sections.
Left unstated, that surface is governed by Flutter's default `PaintingBinding` image cache, sized for a generic app rather than tuned against the brief's explicit "lightweight memory usage" goal or validated on a memory-constrained iOS device under the brief's own performance-first framing.
Concrete failure mode: a channel with a long scrollback of image-heavy messages decodes and retains far more bitmap memory than the brief's memory targets would tolerate, and nothing in the current plan would catch it, because the only decoded-image budget discussed anywhere belongs to a feature that is explicitly not designed in this document.
Fix: state an explicit decoded-image cache budget for the message-list and avatar path, separate from and in addition to whatever the canvas package eventually specifies for itself.

## Moderate findings

### 12. The five/six-package split is asserted, not derived, and reads as a default rather than a choice weighed against a leaner incremental structure

The document argues a real package gives a compiler-enforced public API a folder convention cannot, which is a true statement, but it is also the standard justification offered for this exact package shape in most non-trivial Flutter projects, independent of this project's specific scale.
The brief explicitly warns against a giant monolithic codebase and, in the same breath, asks to "work incrementally... optimize continuously," language that argues for letting package seams emerge from where real coupling pain shows up, not for front-loading five packages plus a reserved sixth before a single feature exists to prove the boundaries are in the right places.
Unlike the stack decision, which walks through what the naive default would be and states explicitly why it is rejected for each of its major calls, this document states the package decision and its benefit without the matching "what happens if we start with fewer packages and split later" analysis.
This is not an argument that the split is wrong, only that it is not shown to be derived from this project's own stated scale rather than carried over as the default shape of "a serious Flutter app."
Fix: add the "why not start smaller and split when the first real coupling problem appears" analysis explicitly, matching the rigor the stack decision applies to its own choices.

### 13. The `api` package pre-builds envelope-dispatch machinery for a binary escape hatch the stack decision explicitly defers to future measurement

`stack-decision.md` reserves a compact binary encoding as "a documented, additive, per-message-type escape hatch for hot paths that measurement later proves need it," language that is deliberately conditional: build it when measurement says to, not before.
`flutter-client.md` has the `api` package's decode layer dispatch on the envelope's type discriminant "before assuming JSON... since the wire format documents a per-message-type binary escape hatch, and building that dispatch in now avoids a rewrite when a hot path adopts it."
That is complexity built today against a branch that, by the stack decision's own words, may never be measured as necessary, which sits uneasily next to the brief's instruction to avoid premature complexity and optimize based on evidence rather than anticipation.
Concrete cost: every message decode carries a discriminated-dispatch branch with exactly one live arm, and every future contributor touching `api`'s decode path has to understand a binary-format seam that does not yet, and may never, have anything on the other side of it.
Fix: either point to the specific measurement that already justifies building this now, or defer the dispatch scaffolding to the point where a real binary hot path is adopted, consistent with the stack decision's own conditional framing.

### 14. No stated trigger for splitting `app` as it accumulates every future screen, repeating the componentization problem one layer up

`app` is described as the composition root holding provider wiring, router, and screens, and it is the only package in the split with no feature-vertical scope of its own the way `design_system`, `data`, and `platform` each have.
As report, block, account settings, admin tooling, and moderation screens all land, none of them named in this document as belonging anywhere else, `app` is where they accumulate by default.
The brief's warning against a giant monolithic codebase applies exactly as much to one package inside a five-package split as it does to a single flat `lib/` tree, if that one package absorbs every screen with no split criterion.
Fix: name a concrete trigger (file count, screen count, or feature count) for extracting a feature-vertical package out of `app`, before it becomes the thing the package split was meant to prevent.

### 15. Golden test scope names theme and viewport variants but omits text-scale variants despite the brief's explicit accessibility requirement

The brief lists accessibility as an explicit UX detail alongside haptic feedback, keyboard navigation, and high-quality transitions, all named as things that must feel polished.
The testing pyramid commits golden tests to "light, dark, and true-black themes... and at least two viewport widths," with no mention of OS text-scale variants anywhere.
A design system that has never been golden-tested at a larger system text scale can silently break layout for exactly the accessibility population the brief calls out by name, and nothing in the stated CI gate would catch it before release.
Fix: add at least one enlarged text-scale variant to the golden matrix, and state the CI time budget the resulting combinatorial growth (themes times viewports times text scale times components) is expected to cost, since the plan already commits to a strict pinned-container-only golden policy that makes regeneration cost a real, non-trivial concern.

### 16. `Result<T, AppError>` and the 300-line file budget are enforced by review convention only, with no CI lint

Both of the plan's two explicitly named code-shape disciplines, the sealed `Result` type at layer boundaries and the 300-line file budget, are stated to be enforced "at review" and by "a repository-layer checklist item in review," with the plan's own risk note admitting the `Result` discipline can "decay back to raw exceptions" without enforcement.
A rule that depends on every reviewer remembering to check it, across years and an unknown number of future contributors, is exactly the kind of guardrail that erodes first, and the plan already knows this about itself, since it names the decay risk explicitly without proposing a mechanical fix for it.
Fix: back at least the `Result`-boundary rule with a lint (a custom `dart analyze` rule, or a grep-based CI check for bare `throw`/`try` in repository and service layers) rather than leaving both of the plan's most safety-critical code-shape rules resting on review discipline alone.

### 17. No battery-specific adaptation policy or battery-drain benchmark is named anywhere

The brief names battery impact as a first-class metric to constantly evaluate, on the same footing as memory and CPU.
`flutter-client.md`'s performance section states CPU, startup, and frame-rate targets in concrete numbers, and says nothing about battery: no Low Power Mode awareness, no reduced-rate fallback for animations or polling under power constraints, and no battery-drain benchmark anywhere in the testing pyramid.
Concrete failure mode: a user enables iOS Low Power Mode expecting every app to visibly back off, and this client, having no stated adaptation policy, keeps its full non-power-saving behavior exactly when the OS and the user have both signaled they want less of it, and no automated test would ever flag the regression since none is planned.
Fix: state at minimum whether Low Power Mode is detected and what, if anything, changes when it is (heartbeat cadence, animation reduction), and add a coarse battery or CPU-time benchmark to the performance testing story.

### 18. No binary size budget is named despite the brief listing binary size as a first-class tracked metric

The brief's performance requirements list binary size alongside memory, CPU, network, and startup as something to constantly evaluate, and the plan discusses cold start, warm start, idle CPU, and frame-rate targets with specific numbers but never states a binary size target for either the iOS or Linux artifact.
A six-package client pulling in Riverpod, Drift, GoRouter, LiveKit's Flutter SDK, and platform-specific windowing and tray plugins has real binary-size exposure that a numeric target would surface early, the same way the numeric startup and frame-rate targets already do for their respective axes.
Fix: state a binary size ceiling per platform and track it in CI the same way the plan already proposes tracking Impeller's enabled state per platform.

## Minor findings

### 19. Keychain-only key storage in this document is not reconciled against "secure enclave" language elsewhere in the research set

This document commits to `flutter_secure_storage`, Keychain-backed on iOS, for device identity key material, which stores an extractable key blob as a Keychain item, a materially weaker guarantee than a non-extractable key generated inside the Secure Enclave via `SecKeyCreateRandomKey` with a Secure Enclave token ID.
Adjacent research describing the same key material uses looser language that reads as if Keychain storage and secure-enclave key generation were interchangeable, and this document does not state explicitly that it is deliberately choosing the weaker of the two for v1.
Fix: state plainly, in this document, that Keychain-backed storage (not Secure Enclave non-extractable key generation) is the deliberate v1 choice, so the gap reads as a decision rather than an oversight.

### 20. libsecret's dependency on a running, unlocked desktop secret service is not addressed as a Linux risk

`flutter_secure_storage` on Linux is backed by libsecret, which requires a running secret-service provider such as `gnome-keyring`, typically unlocked alongside the user's login session.
A user launching the app outside a normal unlocked desktop session (over SSH, in a minimal window-manager setup, or before the keyring unlocks at login) can hit a libsecret call that fails or hangs, and nothing in the plan's Linux platform section anticipates this.
Fix: note the secret-service dependency explicitly and decide what a locked-keyring failure path in the UI looks like, rather than leaving it as a silent assumption of a full, unlocked GNOME session.

### 21. No documented contributor workflow exists for updating an intentionally-changed golden image

The plan correctly bans locally generated goldens from review to avoid cross-machine font rendering flakiness, generating them "only inside a pinned CI container."
It never describes how a contributor who intentionally changed a component is supposed to actually update the corresponding golden image: whether that means downloading a CI artifact, running a specific job, or something else.
Fix: document the update path explicitly, since strict golden discipline with no described update workflow is a predictable source of first-time-contributor friction, in tension with the brief's own "easy to contribute to" goal.

## Open questions the specialist should have raised but did not

- Where does the pre-connect capability handshake for report/block sit in `api`'s connection bootstrap sequence, and which package owns the report, block, and account-deletion screens (see finding 1)?
- Which package owns Linux screen capture, and how does its portal-consent and PipeWire lifecycle differ from the WebRTC capture path on other platforms (see finding 2)?
- What native code, outside the Dart-facing platform package abstraction, is required to satisfy CallKit's synchronous cold-launch reporting contract, and where does it live in the Xcode project (see finding 3)?
- Does LiveKit connection state get its own package and its own public API designed for test injection, or does it stay folded into `platform` (see finding 4)?
- What is `data`'s complete public read surface, including any non-reactive snapshot method intended for high-frequency consumers (see finding 5)?
- What concrete frame-time or dropped-frame threshold on Linux would trigger a Skia fallback decision for Impeller, and what was the actual Linux Impeller status when "required" was written (see finding 6)?
- What automated performance, battery, and voice/screen-share test coverage is planned, and on what cadence (see findings 7 and 17)?
- What single command regenerates all client code generation output, across all packages and both codegen mechanisms, in the correct order (see finding 8)?
- What query-scoping discipline prevents Drift's table-level stream invalidation from turning one channel's write traffic into CPU cost across every open query (see finding 9)?
- What is the client's own data retention and local storage size policy, separate from the attachment cache's already-stated bound (see finding 10)?
- What decoded-image memory budget governs the ordinary message list and avatar path, distinct from the canvas package's own eventual budget (see finding 11)?
