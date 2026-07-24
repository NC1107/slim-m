# Flutter Client Architecture

Scope: the Flutter client only, targeting iOS and Linux (Fedora, GNOME Wayland) first, Android next.
The Voice Canvas is out of scope here; it reserves a package boundary but its internals belong to a separate track.
Every choice below is weighed against the brief's priorities: performance, componentization, self-hostability, and long-term maintainability, and against the already-locked server stack (Rust/Axum/SQLite, UUIDv7 identity plus a monotonic per-scope sequence number, JSON wire format with schema-first Dart and Rust codegen).

## Package and module structure

Decision: a single Dart pub workspace (stable since Dart 3.6, no Melos) holding several small path-dependency packages rather than one flat `lib/` tree.
Packages: `api` (schema-generated models plus a thin hand-written client wrapping `package:http` and the WebSocket socket, not a fully generated Retrofit-style client, since auth-refresh and reconnect-backoff need hand control), `design_system` (tokens, `ThemeExtension`s, the Lucide icon wrapper, reusable widgets), `data` (SQLite schema and repositories keyed by UUIDv7 with the server sequence as sync cursor), `platform` (per-OS interfaces and implementations), and `app` (composition root: provider wiring, router, screens).
A `voice_canvas` package boundary is reserved but not designed here.
A real package gives a compiler-enforced public API a folder convention cannot; pub workspaces get that without a third build tool.
Inside each package, organize by feature vertical slice, with a soft 300-line file budget enforced at review.
The `api` package's decode layer dispatches on the envelope's type discriminant before assuming JSON, since the wire format documents a per-message-type binary escape hatch, and building that dispatch in now avoids a rewrite when a hot path adopts it.
Risk: multi-package builds add setup overhead, mitigated by a small, stable package count.

## State management and dependency injection

Decision: Riverpod with code generation (`Notifier`/`AsyncNotifier`), and no separate DI container.
Serious current options are Riverpod, Bloc/Cubit, the `signals` package, and GetX.
Bloc's event/state boilerplate is a poor match for a chat app's mostly CRUD-shaped async streams, and still needs `get_it` or similar alongside it for DI.
Signals gives fine-grained reactivity with less ceremony but a smaller ecosystem and no standardized DI story, a real risk for a project meant to outlive its first maintainer.
GetX is rejected outright for global service-locator state and weak testability.
Riverpod's provider graph is itself the DI graph: the HTTP client, socket client, database, and repositories are providers, overridden cleanly in tests, so `get_it`/`injectable` would be a second, runtime-typed graph duplicating a compiler-checked one.
Risk: `build_runner` adds a build step and occasionally opaque errors, mitigated by small per-package builds.

## Navigation

Decision: GoRouter with shell routes for the persistent sidebar, using hand-written typed route constants rather than its optional `go_router_builder` codegen.
The wire format already forces one codegen pipeline and Riverpod a second; a third generator for routing is not worth the marginal type safety.
GoRouter integrates with Riverpod for auth-gated redirects and its nested shell routes map onto the Discord/Slack-style layout the brief asks for.
Risk: redirect logic tends to sprawl into one function, mitigated by small, independently tested redirect guards.

## Offline-first local storage and caching

Decision: SQLite via Drift as the single source of truth for conversations, messages, channels, and settings, with rows keyed by UUIDv7 and an indexed sequence column used for ordering and as the resume cursor on reconnect.
Every write path (WebSocket push and REST catch-up) is an idempotent upsert by UUIDv7, so a reconnect race cannot duplicate or reorder rows.
Chat data is relational; Drift gives indexed, paginated, compile-time-checked SQL with reactive `Stream` queries, mirroring the server's own compile-time-checked-query discipline end to end rather than forcing in-memory filtering as history grows.
Alternatives rejected: Isar (maintenance continuity concerns), ObjectBox (native binary per platform, closed-core, non-SQL query surface), raw `sqflite` (no type safety, no reactivity).
Attachments cache to disk as content-addressed files with a bounded LRU eviction policy, keeping disk footprint predictable.
Device identity key material uses `flutter_secure_storage` (Keychain on iOS, libsecret on Linux), pre-wired for the deferred opt-in E2EE.
Risk: Drift's codegen stacks with Riverpod's and the schema generator, mitigated by running all generators in one CI pass.

## Theming and design tokens

Decision: one token source file (color roles, spacing, radius, type scale, motion) compiled to Dart constants and consumed only through `ThemeExtension`, never a hardcoded value in a widget.
Because the brief leaves visual design open and the owner requires a designer review before token lock, the pipeline is built now so a designer's final values drop in without touching widget code.
Light, dark, and a true-black variant ship for OLED battery savings.
Lucide icons are wrapped behind an internal `AppIcons` class rather than referenced directly, so an icon-set change never ripples through feature code, and a CI check greps `lib/` for emoji literals to enforce the no-emoji-as-chrome rule mechanically.
Risk: token file and generated Dart drifting apart, mitigated by a CI check that fails the build on mismatch.

## Platform integration

Decision: a `platform` package of small abstract interfaces (notifications, secure storage, window management, call integration) with per-OS implementations, never `Platform.isX` checks scattered in feature code.
iOS gets CallKit and PushKit integration for cold-launch VoIP wake from the relay, and Keychain-backed storage.
Linux gets an actively maintained window/tray package, tested explicitly on Fedora's GNOME Wayland session rather than X11 only, since that is the brief's environment and Wayland is where Flutter-on-Linux plugins are thinnest.
Android's seam (foreground service, FCM registration into the push relay) is designed now, implemented in that phase.
Risk: the Linux plugin pool has fewer maintainers than mobile's, mitigated by picking only actively maintained packages and re-validating on Fedora each SDK bump.

## Startup and rendering performance

Decision: nothing heavy (database open, key unlock, socket connect, API client construction) runs before first frame; a splash renders immediately and heavy init happens async after.
Impeller is required, and its enabled state is verified per platform in CI rather than assumed, since its maturity differs between iOS and Linux.
Any high-frequency UI stream (typing indicators, presence, scroll position, not just canvas) bypasses the wide provider tree through a narrow `ChangeNotifier`/`ValueListenable` island under a `RepaintBoundary`, so one hot widget cannot fan out rebuilds across the tree.
Long lists always use builders or slivers with tuned cache extents.
There is no polling; WebSocket push plus reactive local queries are the only update path.
Targets: cold start under 1.5 seconds on a mid-tier phone or Fedora laptop, warm start under 500 milliseconds, near-zero idle CPU, sustained 60fps on standard displays and 120fps on ProMotion.

## Error handling

Decision: a sealed `Result<T, AppError>` type at repository and service boundaries instead of exceptions crossing layers, plus a global `FlutterError.onError`/`PlatformDispatcher.onError` hook feeding structured local logs.
The server's schema-defined error responses decode directly into `AppError` variants through the generated `api` models, so the error taxonomy is shared with the server rather than duplicated by hand.
Crash reporting is opt-in and defaults off, especially for self-hosted builds, matching the project's privacy stance.
A typed `Result` forces every call site to acknowledge failure at compile time, where try/catch discipline erodes over a codebase's lifetime.
Risk: `Result` discipline decaying back to raw exceptions, mitigated by a repository-layer checklist item in review.

## Testing pyramid

Unit tests carry the bulk of coverage: repository and mapping logic, Riverpod provider logic via `ProviderContainer`, and SQL queries against in-memory sqlite3, all without a widget tree.
Widget tests cover every reusable `design_system` component with fakes injected through `ProviderScope`.
Golden tests cover `design_system` components and key screens across light, dark, and true-black themes and at least two viewport widths, generated only inside a pinned CI container to avoid font flakiness.
Integration tests use `integration_test` against a real local server for critical flows: invite-based account creation, send and receive a message, and reconnect-and-resync via the sequence cursor.
Because the wire format is schema-first and shared, `api` also gets fixture-decode tests fed by the same JSON Schema examples the Rust server tests against, catching client/server drift early.

## Flags on the given foundational stack

Two points worth raising rather than relitigating.
First, `dart:io`'s WebSocket client supports permessage-deflate, but interop between two independent deflate implementations is a known bug source; this needs an explicit early interop test, not an assumption that RFC 7692 compliance on both ends is sufficient.
Second, Keychain/libsecret-only key storage (not Secure Enclave non-extractable key generation) is accepted for v1, but the client's key-storage interface should be shaped now so a future move to hardware-backed non-extractable keys, needed for opt-in E2EE to mean anything cryptographically, does not require an interface change later.
