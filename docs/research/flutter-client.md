# Flutter Client Architecture

Scope: the Flutter client only, targeting iOS and Linux (Fedora) first, Android next.
Every decision below is weighed against the brief's stated priorities: performance, componentization, self-hostability, and long-term maintainability over shipping speed.
Where relevant I draw on the echo-messenger reference notes, since that project already paid for several of these lessons in production.

## Project and package structure

Decision: a Melos-managed monorepo of small path-dependency packages, not one `lib/src/` tree.
Packages: `design_system` (tokens, theme, reusable widgets), `data` (Drift schema, repositories, DTOs), `platform` (per-OS integration behind interfaces), `voice_canvas` (isolated, the signature feature), and `app` (router, DI wiring, screens).
Inside each package, organize by feature vertical slice, not technical layer, with a soft 300-line file budget enforced at review.
A real package boundary forces an explicit public API, which folder convention alone cannot enforce.
Isolating `voice_canvas` matters because it is the highest-risk, most-audited subsystem in the reference project, and it earns its own focused test suite.
Rejected: a single layered package (`lib/screens`, `lib/providers`, echo's original shape) invites the cross-feature coupling the brief warns against, and a ten-plus micro-package split is needless ceremony.
Risk: multi-package builds add setup overhead, mitigated by keeping the package count small and using path dependencies only.

## State management: Riverpod

Decision: Riverpod with code generation (`riverpod_annotation`/`riverpod_generator`), using `Notifier`/`AsyncNotifier`, matching echo's own choice.
It gives a compile-time-checked provider graph, no `BuildContext` needed for access, trivial test overrides, and it does not fight the "hot-path data bypasses state management" pattern the reference project proved necessary for canvas dragging.
The team also has deep operational experience with it at this scale, which outweighs any theoretical edge a greenfield choice might offer.
Rejected: Bloc adds event/state boilerplate for no matching benefit here, and GetX is rejected outright for global service-locator state and poor testability.
Risk: `build_runner` codegen adds a build step and occasionally opaque errors, mitigated by small per-package builds and a documented codegen contract.

## Navigation

Decision: GoRouter, with shell routes for the persistent sidebar and typed route definitions.
It is declarative, integrates with Riverpod for auth-gated redirects, and its nested shell routes map directly onto the Discord/Slack-style layout the brief asks for.
Rejected: hand-rolled Navigator 2.0 is boilerplate with no upside, and auto_route's extra codegen is not worth stacking on Riverpod's.
Risk: redirect logic tends to sprawl into one tangled function, mitigated by small, independently tested redirect guards.

## Dependency injection

Decision: no separate DI container.
Riverpod's provider graph is the DI graph: services (HTTP client, WebSocket client, Drift database, repositories) are themselves providers, overridden in tests.
Adding get_it or injectable on top would be a second, competing graph resolved by runtime type instead of the compiler, pure duplication for no benefit.
Risk: deep service chains can get hard to trace, mitigated by keeping services as plain constructor-injected classes with a thin provider wrapper at the edge.

## Offline-first local storage

Decision: Drift (SQLite) as the single source of truth for conversations, messages, channels, and canvas cache, with `flutter_secure_storage` for key material and `shared_preferences` for settings.
Riverpod `StreamProvider`s watch Drift queries directly, and server writes flow through the repository layer into Drift, giving reactive offline reads for free.
Chat data is inherently relational, and Drift gives indexed, paginated SQL with reactive streams, where a flat key-value store forces in-memory filtering as data grows and fights the brief's "efficient database queries" goal.
Rejected: Hive, echo's choice, is unmaintained upstream with no real query capability.
Isar's original maintainer wound down active development, an unacceptable risk for a maintainability bet.
ObjectBox adds a native binary dependency per platform and a smaller community than Drift.
Risk: Drift's codegen stacks with Riverpod's, mitigated by running both generators in one pass and keeping schema files small.

## Theming and design tokens

Decision: one token source of truth (a JSON/YAML file, loosely W3C Design Tokens shaped) compiled into Dart constants, wired into Flutter through a `ThemeExtension`, with light, dark, and a true-black variant for OLED battery savings.
No widget reads a hardcoded color or spacing value.
Visual design is undecided in the brief, so a token file lets a future designer's output land without touching widget code, and `ThemeExtension` is Flutter's sanctioned mechanism for custom theme data, already validated in echo's history.
Rejected: hardcoded values scattered through widgets, which echo explicitly moved away from, and a runtime user-customizable theming engine, premature scope for launch.
Risk: token drift between the source file and generated Dart, mitigated by a CI check that fails the build if they are out of sync.

## Platform integration

Decision: a `platform` package exposing small abstract interfaces with per-OS implementations, never scattered `Platform.isX` checks in feature code.
iOS gets CallKit integration and Keychain-backed secure storage.
Linux gets a system tray/window-manager package and libsecret-backed secure storage, tested explicitly on Fedora's GNOME Wayland session, not just X11, a real Flutter-on-Linux rough edge.
Android's seam (foreground service, FCM registration into the push relay) is designed now but not built until that phase.
This mirrors the abstraction that let echo contain CallKit and foreground-service chaos behind one guarded notifier instead of leaking quirks into shared providers.
Risk: the Linux plugin ecosystem has a thinner maintainer pool than mobile's, mitigated by picking actively maintained packages and re-evaluating each SDK bump.

## Rendering and startup performance

Decision: nothing heavy (crypto init, DB open, WebSocket connect) runs before first frame, mirroring echo's splash-then-async-init pattern.
Impeller is the required renderer, verified enabled per platform rather than assumed.
The three-layer RepaintBoundary plus off-Riverpod `ChangeNotifier` pattern proven on echo's canvas becomes the standard for any high-frequency UI, not just canvas: audio meters, drag-reorder, typing indicators.
Long lists always use builders or slivers, and there are no polling timers, WebSocket push plus the reactive provider graph only.
Targets: cold start under 1.5 seconds on a mid-tier phone or Fedora laptop, warm start under 500 milliseconds, near-zero idle CPU, and sustained 60fps (120fps on ProMotion) during canvas drag and pan.
Risk: Impeller's maturity differs by platform, mature on iOS, still evolving on Linux, tracked at each SDK upgrade.

## Error handling

Decision: a small hand-rolled sealed `Result<T, AppError>` type at repository and service boundaries instead of raw exceptions crossing layers, plus a global `FlutterError.onError`/`PlatformDispatcher.onError` hook feeding structured logs.
Crash reporting is opt-in and defaults off for self-hosted deployments, matching the project's self-hosting and privacy stance.
The reference project's worst bugs were silent failures, a dropped stroke from a decode-type mismatch, a silently dropped non-authority write, and a typed Result forces every call site to acknowledge failure at compile time rather than relying on try/catch discipline that erodes.
Rejected: exceptions-only control flow, exactly the bug class that bit echo, and a full functional-programming toolkit (fpdart `Either` everywhere), a learning-curve tax against the brief's "easy to contribute to" goal for little extra benefit.
Risk: Result discipline decays back into raw exceptions without enforcement, mitigated by a repository-layer checklist item in review.

## Testing pyramid

Decision: unit tests carry the bulk of coverage (gesture state machines, Result mapping, Drift queries against in-memory sqlite3, Riverpod provider logic via `ProviderContainer`, no widget tree).
Widget tests cover every reusable design-system component with fakes injected through `ProviderScope`.
Golden tests cover design-system components and key screens across light and dark themes and at least two viewport widths, generated only inside a pinned CI container to avoid cross-machine font flakiness.
Integration tests use `integration_test` against a real local server for critical flows: login, send message, join a voice call, and a two-client canvas draw-sync smoke test modeled on echo's own audit scripts.
This mirrors the shape that worked at scale in the reference project, while adding golden-test discipline echo's notes do not describe, justified by the brief's explicit polish ambition.
Canvas, voice, and sync-critical modules get a documented minimum coverage floor from day one, since those are the modules the reference project's history shows are highest risk.
Risk: golden tests are sensitive to cross-machine font rendering, mitigated by never accepting locally generated goldens in review.

## A brief concern worth flagging

The brief calls the Voice Canvas "infinite."
Echo's history shows this is a real trap: its canvas started at 100,000px, shrank to 4096px, then to a 6000px fixed square, and its own architecture assessment named a true unbounded canvas a dead end without a per-object data model and viewport virtualization.
A genuinely infinite canvas is not a rendering detail, it requires tiled rendering with load and cull by visible bounds, a materially larger architecture than a single fixed `CustomPaint` surface.
I recommend scoping this as very large and effectively unbounded for practical use, similar to Figma's own generous-but-bounded canvas, and treating true infinite tiling as a later phase once the per-object data model and sequence-numbered sync exist to support it.
Building for true infinity before sync and data model problems are solved risks repeating echo's exact sequence of premature scale changes.
