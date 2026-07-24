# Flutter Client Plan: Adversarial Review

Target document: `docs/research/flutter-client.md`.
Cross-checked against `docs/BRIEF.md`, the sibling reports in `docs/research/` (`voice-canvas.md`, `realtime-sync.md`, `security.md`, `database.md`, `backend.md`, `performance.md`, `ux.md`, `oss.md`, `devops.md`, `appstore.md`, `design-language.md`, `networking-relay.md`), and the echo-messenger reference notes (`decentralized-chat-app/reference-echo-messenger.md`) plus its `docs/voice-lounge/*` decision-of-record folder and `check-in-relay`'s own reference notes.

Severity key: critical findings would force a redesign of the plan as written.
Major findings are real defects that should block sign-off until addressed.
Moderate findings are real costs or gaps that do not block the overall direction but should be resolved before implementation starts.
Minor findings are worth fixing but low risk either way.

## Critical findings

### 1. The plan's own storage decision contradicts its own hot-path rule, for the app's signature feature

`flutter-client.md` states Drift is "the single source of truth for conversations, messages, channels, and canvas cache" and that "Riverpod `StreamProvider`s watch Drift queries directly," giving "reactive offline reads for free."
The same document, one section later, states the opposite principle for anything high-frequency: "off-Riverpod `ChangeNotifier` for all high-frequency UI, not just canvas," and cites the canvas's in-flight stroke bypassing state management entirely as the pattern to generalize.
`voice-canvas.md` then designs the actual canvas render loop around a uniform-grid **in-memory** spatial index "queried each frame against the expanded viewport rect," explicitly not a database query, with a 2ms-per-pointer-sample repaint budget and 60fps (120fps ProMotion) targets at up to 20,000 resident objects.

These two statements are not reconciled anywhere in the document.
Read literally, "Riverpod StreamProviders watch Drift queries directly" for the canvas cache means the canvas's pan/zoom/draw loop is wired to SQLite queries through Riverpod, exactly the pattern the document itself names as the single biggest anti-pattern to avoid for high-frequency UI, and exactly the pattern `voice-canvas.md` was written to avoid by building a separate in-memory spatial index.
A team implementing this plan as written has no way to know whether Drift is the render-time data source for canvas objects (which would blow every canvas performance budget in `voice-canvas.md` and `performance.md`) or purely an offline persistence and cold-start hydration layer that feeds a separate in-memory structure the client actually paints from (which is almost certainly what is intended, but is never stated).
This is exactly the class of ambiguity that produced echo's own canvas rewrite: a plausible-sounding architecture note that nobody pressure-tested against the frame budget until it shipped and had to be redone.
The plan needs one explicit paragraph: Drift persists and hydrates, an in-memory structure (grid index plus a plain notifier, not a `StreamProvider`) is what the paint layer reads from at 60fps, and Drift writes are batched/async off the render path entirely.
Without that paragraph, whichever engineer wires up the canvas package first decides this by accident, and getting it wrong here forces the same kind of targeted rewrite echo's own history shows this exact gap causes.

## Major findings

### 2. The Secure Enclave guarantee `security.md` promises is not what the chosen plugin delivers

`security.md` states the identity keypair anchoring future E2EE and push-payload encryption "stays in the platform keystore or secure enclave."
`flutter-client.md` names the actual mechanism: `flutter_secure_storage` for key material on iOS, backed by Keychain.
`flutter_secure_storage` stores values as Keychain items; it does not generate non-extractable keys inside the Secure Enclave, which requires `SecKeyCreateRandomKey` with `kSecAttrTokenID: kSecAttrTokenIDSecureEnclave` and is a materially different (and stronger) guarantee than Keychain storage of an extractable key blob.
The two reports' wording ("keystore or secure enclave," then just "Keychain") reads as if these are interchangeable, and they are not: a Keychain item is recoverable by any code path with the right entitlement and device state, while a true Secure Enclave key can never leave the hardware even in principle.
For an identity key meant to anchor future end-to-end encryption, this gap is worth resolving explicitly, either by accepting Keychain-only as sufficient for v1 and saying so, or by scoping the small amount of native code an actual Secure Enclave-backed key would require.

### 3. LiveKit ownership is never assigned to any of the five packages

The project structure section names exactly five packages and states that a real package boundary "forces an explicit public API."
It never says which package owns the LiveKit client wrapper: connection lifecycle, mic/camera/deafen state, active-speaker tracking, CallKit bridging on iOS, and the eventual Android foreground service integration.
In echo, this single component (`livekit_voice_provider.dart`) is roughly 1200 lines and a named complexity and crash-class hotspot (re-entrant leave/rejoin races, `_disposed` flag guards).
Is it inside `voice_canvas` (the UX surface it renders into), `platform` (the OS-adjacent permissions and CallKit surface it needs), or an unnamed sixth package?
Each answer has different coupling consequences: putting it in `voice_canvas` ties the canvas package to WebRTC/SFU concerns unrelated to drawing and rendering; putting it in `platform` ties an OS-abstraction package to a specific third-party media SDK.
Leaving it unassigned in the very document whose central claim is that package boundaries prevent exactly this kind of ambiguity is a real omission for the single highest-complexity subsystem the reference project has already burned time on.

### 4. CallKit's synchronous native requirement is understated as a "Dart interface" problem

`flutter-client.md` frames platform integration as "small abstract interfaces with per-OS implementations," with "iOS gets CallKit integration" listed as one line alongside Keychain-backed secure storage.
`networking-relay.md` treats the same requirement very differently: "every VoIP push must report an incoming call to CallKit synchronously... a wrong call here is an App Store risk, not just a UX regression, so the CallKit-report invariant needs a test, not a code review comment," citing Apple's actual 2015-2016 entitlement-revocation enforcement history.
A cold-launch VoIP push (app fully terminated) must report to CallKit from the native PushKit delegate before the Flutter engine and Dart isolate have necessarily even spun up; this is not something an "abstract Dart interface with a per-OS implementation" can fully own, because part of the correctness contract must execute in native Swift code that runs before Flutter's runtime is guaranteed to be alive.
The report's framing implies this is bounded, testable Dart-facing plugin surface like Keychain access; in practice it is a genuine native-code integration with a hard real-time constraint whose violation carries the specific entitlement-revocation consequence `networking-relay.md` already names.
This needs explicit scoping in the client plan (a minimal native AppDelegate/PushKit delegate that reports to CallKit before touching the Flutter engine), not an implicit assumption that it falls out of the platform-package pattern.

### 5. Fedora GNOME Wayland, the plan's own primary Linux target, is the one desktop where a system tray does not exist by default

`flutter-client.md` commits to testing tray/window-manager integration "explicitly on Fedora's GNOME Wayland session, not just X11."
Stock GNOME (the desktop the brief and this report both name as primary) removed the system tray entirely; `AppIndicator`/legacy tray icons only render if the user has separately installed a GNOME Shell extension, which a default Fedora Workstation install does not have.
A chat app's common "close window, keep running for notifications" pattern depends on a tray affordance to tell the user the app is still alive and to let them reopen it.
On the plan's own named primary test environment, that affordance silently does not appear unless the user has already installed an unrelated extension, which is a real, concrete gap the "tested explicitly on Wayland" claim does not surface: testing on a real vanilla GNOME Wayland session should have caught this, since it is not an edge case, it is the default state of the named target.

### 6. App Store-mandated compliance screens are entirely absent from the package and screens plan

`security.md` and `appstore.md` both name report, block, and in-app account deletion as review-blocking, ship-at-launch requirements (Guidelines 1.2 and 5.1.1), not optional moderation nice-to-haves; `appstore.md` states them plainly: "ship at launch, not later: report, block, and a moderation queue."
`flutter-client.md`'s project-structure section discusses screens, routing, and permission-flag surfaces (down to naming individual flags like `canvas-edit`) but never once mentions where report/block/delete-account UI lives, which package owns it, or that it belongs in the testing pyramid's widget or integration coverage.
Given the brief names iOS as a primary initial testing platform and `appstore.md` treats these flows as a hard App Store dependency for that platform, their complete absence from the client architecture document is a real gap: this is client-rendered, review-blocking surface area with no assigned home in the one report whose job is to plan client screens and packages.

### 7. The claimed "day one" test-coverage floor for canvas and voice is not actually achievable as designed

`flutter-client.md` states canvas, voice, and sync-critical modules "get a documented minimum coverage floor from day one."
The echo reference notes document exactly why this is hard in practice: the join/leave/rejoin race in the LiveKit voice notifier has no execution test today specifically because "it needs a `Room`-injection seam... that doesn't exist yet," since join always creates a real LiveKit `Room` and touches native mic permissions and CallKit (issue #1329).
`flutter-client.md`'s testing section never mentions designing that injection seam into the platform or voice package's public API, so the plan repeats the precise precondition that made this untestable in the reference project, while simultaneously promising day-one coverage for exactly this bug class.
A coverage floor is only real if the public API of the owning package is designed to be testable in the first place; that design step is missing.

### 8. The project's central lesson (ordering) is applied to canvas but not to the client's own local sync merge

Every sibling report treats "apply events by server-assigned order, not arrival order" as the single most important lesson from echo, and `voice-canvas.md`, `realtime-sync.md`, and `database.md` all apply it carefully to canvas ops and messages on the server side.
`flutter-client.md` never addresses the equivalent client-local problem: `realtime-sync.md`'s WebSocket push and its `GET /api/sync?after=<last_id>` catch-up cursor are two separate channels that can both write the same events into the client's Drift tables, for instance on a reconnect that races a backlog fetch against live WS delivery of the same messages.
Global snowflake IDs make an idempotent upsert-by-id the obvious fix, but the plan does not say so, and a naive "insert every event Drift receives" implementation (the default shape of "server writes flow through the repository layer into Drift" as currently worded) can double-insert or misorder rows exactly the way echo's canvas did, just relocated to the client's local cache instead of the server's op log.
This is the one place the plan's own stated design philosophy (learn from echo's ordering bugs) should have been applied to its own local-storage design and was not.

## Moderate findings

### 9. The plan's own core discipline rules are enforced by review, not by tooling, while a sibling report already demonstrates why that fails

The 300-line file budget is "enforced at review."
The `Result<T, AppError>` discipline is "mitigated by a repository-layer checklist item in review," with the plan's own risk note admitting it "decays back into raw exceptions without enforcement."
`oss.md`, written to sit alongside this plan, independently concludes that the file-budget rule specifically needs to become "a CI-enforced lint rule requiring an explicit override comment... so the guardrail survives past the point where the owner can review every PR personally," which is a direct, if implicit, rebuttal of `flutter-client.md`'s own enforcement choice for the identical rule.
No equivalent hardening is proposed for the Result-type rule anywhere in the research set, despite it guarding against the exact bug class (silent failures) the plan calls echo's worst.
A project explicitly optimizing for multi-year, multi-contributor maintainability should not leave its two most safety-critical code-shape rules resting on review discipline alone.

### 10. Impeller-on-Linux risk is named but has no fallback plan for the one workload most exposed to it

The plan is honest that "Impeller's maturity differs by platform, mature on iOS, still evolving on Linux," but stops at "tracked at each SDK upgrade."
The workload most exposed to renderer differences is exactly the one the plan spends the most words on: a `CustomPaint`-heavy, multi-layer, high-frequency canvas.
If Impeller-on-Linux underperforms or regresses for this specific workload at the time of implementation, the plan gives no fallback rendering path, no acceptance test that would trigger a fallback decision, and no statement of which Flutter version's Linux Impeller status was actually checked when this recommendation was written.
"Verified enabled per platform rather than assumed" is a good instinct for launch day; it says nothing about what happens if verification fails specifically on the canvas.

### 11. Golden-test scope for font scaling is contradicted between two dependent reports, and the owning report is silent

`flutter-client.md`, the report that owns the testing pyramid, commits only to "light and dark themes and at least two viewport widths" for golden tests, with no mention of font-scale variants at all.
`ux.md` layers a font-scaling requirement on top, citing this document as the mechanism: "font scaling to 200 percent, verified by golden tests at 1x, 1.3x, and 2x."
`design-language.md` separately states text must respect "OS text-scale up to 130 percent without breaking layout, verified by the golden tests already planned in `flutter-client.md`."
Both dependent reports cite `flutter-client.md` as already covering this, and it does not, and the two dependent reports disagree with each other on the actual number (130 percent versus 200 percent).
Beyond the inconsistency itself, the combinatorics are real: two themes times two-plus viewports times up to three font-scale steps is a double-digit golden-image count per component before any component-specific state variants are added, with no stated budget for the resulting CI time or "regenerate goldens" review burden this plan's own strict pinned-CI-only policy will produce.

### 12. No stated policy for splitting `app` as it grows, the exact monolith risk the package split was meant to prevent

The five-package split names `app` as the package holding "router, DI wiring, screens."
As groups, DMs, admin tooling, and moderation UI (all named elsewhere in the research set) land, `app` is the package that absorbs all of them, since no other package is scoped to own a vertical feature slice the way `voice_canvas` is.
The brief's explicit warning ("avoid creating a giant monolithic codebase... work incrementally, keep responsibilities separated") is aimed at exactly this failure mode, just one layer up: five packages does not prevent one of the five from becoming the new monolith if there is no stated trigger (screen count, file count, or feature count) for splitting `app` further as the product grows past its initial scope.

### 13. Melos plus two stacked codegen tools across five packages has a real CI and onboarding cost that is never estimated

The plan names the risk qualitatively ("build_runner codegen adds a build step," "Drift's codegen stacks with Riverpod's") but gives no cost estimate.
Five packages means five separate `.dart_tool` caches and, potentially, five separate `pubspec.yaml` SDK constraint declarations that must be bumped in lockstep on every Flutter/Dart SDK upgrade; two codegen tools running per package multiplies the surface for the "delete `.dart_tool` and retry" class of contributor friction relative to a single-package app running one generator.
`oss.md` states the explicit goal "easy to contribute to"; a first-time contributor fixing a UI bug in `design_system` who has never used Melos before is a real persona this plan does not model the onboarding cost for.

### 14. The plan is scoped for a team, but the project's own governance report says the maintainer is one person today

`oss.md` states plainly: "a single owner acting as maintainer today."
`flutter-client.md` proposes, before a single feature ships: five Melos packages, two stacked code generators, GoRouter with typed routes, a Result-type discipline layer, golden tests across a still-undetermined theme/viewport/font-scale matrix, widget tests for every design-system component, and integration tests against a real local server including a two-client canvas sync smoke test.
The brief does explicitly deprioritize shipping the fastest MVP in favor of thoughtful architecture, which is a real, stated justification for investing ahead of need, and this review does not dispute that instruction.
What the plan does not provide, and arguably should, is any phased "what a single maintainer actually builds first" subset distinguishing scaffolding that must exist before the first commit from scaffolding that can follow once a second contributor or real usage arrives; without that phasing, the well-known open source failure mode is over-building the skeleton and never reaching a shippable v1, which is precisely what heavy up-front architecture risks if resourcing is not addressed alongside it.

## Minor findings

### 15. No named crash-reporting vendor, and the obvious default choices conflict with the project's own stance

The plan says crash reporting is "opt-in and defaults off for self-hosted deployments" but names no provider.
If the eventual choice is a mainstream SaaS default such as Firebase Crashlytics, that pulls in a Google SDK and, on Android, Google Play Services dependencies, both in tension with the project's self-hosting and privacy stance and with its binary-size and startup budgets.
A self-hostable, open-source-friendly option (for example a GlitchTip-style self-hosted Sentry-compatible target) fits the project's own AGPL-server, self-host-first posture noticeably better and is worth naming explicitly rather than leaving as an implicit future choice.

### 16. The contributor workflow for updating golden tests is never described

The plan correctly bans locally generated goldens from review, to avoid cross-machine font flakiness.
It does not describe how an external, first-time contributor is actually supposed to update a golden image they intentionally changed: whether that means triggering a specific CI job and downloading an artifact, a documented script, or something else.
Strict golden discipline without a documented update path is a known source of contributor friction, in direct tension with the project's stated "easy to contribute to" goal.

## Open questions the specialist should have raised but did not

- Is Drift the render-time data source for the Voice Canvas, or purely a persistence and hydration layer feeding a separate in-memory structure the canvas actually paints from (see finding 1)?
- Which package owns the LiveKit client wrapper, and what is its public API surface designed to make testable from day one (see findings 3 and 7)?
- What native code, outside the Dart-facing platform package abstraction, is required to satisfy CallKit's synchronous cold-launch reporting contract (see finding 4)?
- What is the actual behavior of the client on a stock GNOME Wayland session with no tray-icon extension installed (see finding 5)?
- Where do report, block, and account-deletion screens live, and are they covered by the testing pyramid (see finding 6)?
- What idempotency or ordering guarantee governs writes into Drift when WebSocket push and REST catch-up sync race on reconnect (see finding 8)?
- What is the actual target font-scale range and golden-test variant count for accessibility, reconciled across `flutter-client.md`, `ux.md`, and `design-language.md` (see finding 11)?
- What minimal client scope is intended for a single maintainer to build first, versus scaffolding that can follow once the contributor base grows (see finding 14)?
