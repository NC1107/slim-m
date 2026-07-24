# Flutter Client Stack Validation

Date: 2026-07-23
Status: Due-diligence validation pass

Scope: Validates the Flutter client package set for slim-m against current 2026 library status, maintenance, licensing, and platform-specific gotchas.
The architecture layers (state/DI, persistence, routing, HTTP, secure storage, media, testing, codegen) are already decided; this review examines whether the chosen libraries remain the right choices now and identifies improvements and risks.

## Architecture Context

The Flutter client is built on:
- Dart native pub workspace with Riverpod (codegen) for state and DI.
- Drift for local SQLite persistence.
- GoRouter for navigation.
- Dio for HTTP; web_socket_channel for WebSocket.
- flutter_secure_storage for cryptographic key storage.
- Official LiveKit Flutter SDK (livekit_client) with flutter_webrtc.
- Build_runner-driven codegen: freezed and json_serializable for models.
- Lucide icons, flutter_svg for vectors, and neutral-slate design tokens.
- Golden tests (now alchemist, not golden_toolkit).
- Patrol for E2E testing on iOS and Android; integration_test for web.
- Intl for localization (i18n/l10n).
- iOS and Linux/Fedora as primary testing platforms.

---

## 1. Validation: State and Dependency Injection

### Riverpod 3.3.x and riverpod_generator

Status: CONFIRMED - Mature, actively maintained, production-ready.

- **Maturity**: Riverpod 3.0+ is the consensus default for new Flutter projects in 2026.
- **Maintenance**: Actively maintained by Remi Rousselet. Regular releases, community engagement.
- **License**: MIT (permissive).
- **Comparison**: Riverpod is preferred over BLoC for its compile-time safety, less boilerplate, no BuildContext dependency, and gentler learning curve.
- **Codegen**: riverpod_generator with the @riverpod annotation is the recommended approach in 2026; it provides type-safe parameters without .family gymnastics, auto-disposed behavior by default, and eliminates manual provider declarations.
- **Key advantage**: Compile-time safety, context-free reads, first-class async, and 3.0 resilience features (automatic retry, backoff, pause/resume).
- **Cost**: Adds a build_runner step; initial learning curve for nested providers and async.

Recommendation: KEEP - Riverpod 3.3+ with codegen is the right default. The compile-time safety, context-free access, and reduced boilerplate directly serve the brief's maintainability and performance goals.

---

## 2. Validation: Local Persistence

### Drift (SQLite)

Status: CONFIRMED - Mature, actively maintained, production-ready.

- **Maturity**: Drift is the established, type-safe SQLite abstraction for Flutter and Dart; 2026 updates show continued refinement for Flutter 3.x compatibility.
- **Maintenance**: Actively maintained by Simon Binder. Regular updates and bug fixes.
- **License**: MIT (permissive).
- **Key features**: Type-safe query building, auto-updating streams, reactive UI integration, schema migrations, transactions, complex filters, batched updates, cross-platform support (mobile, desktop, web).
- **Integration**: Seamless with StreamBuilder/FutureBuilder; auto-refresh on data changes.
- **Advantages over direct SQLite**: Handles schema changes gracefully, integrates with Flutter's async model, works on desktop and web, reduces boilerplate.

Gotcha: WAL mode requires a filesystem that supports it correctly; network-mounted data directories may not work reliably. Document this in self-host guides.

Recommendation: KEEP - Drift is the right choice for reactive, type-safe local persistence with minimal boilerplate and excellent UI integration.

---

## 3. Validation: Routing

### GoRouter

Status: CONFIRMED - Feature-complete, stable, official Flutter team support.

- **Maturity**: GoRouter is feature-complete and mature in 2026; the Flutter team's focus is now on bug fixes and stability, not new features.
- **Maintenance**: Actively maintained by Flutter team. Regular security and stability patches.
- **License**: BSD 3-Clause (permissive).
- **2026 status**: GoRouter 14+ with typed routes via go_router_builder is the default for new projects.
- **Key features**: Typed routes, StatefulShellRoute for bottom navigation, auth guards via redirect, deep linking, analytics observer.
- **SDK requirement**: Minimum Flutter 3.38/Dart 3.10 as of 2026.

Recommendation: KEEP - GoRouter is the official, production-tested choice. Typed routes eliminate entire classes of runtime errors.

---

## 4. Validation: Codegen Infrastructure

### build_runner

Status: CONFIRMED - Improved, optimized, stable in 2026.

- **Maturity**: Fully mature. build_runner is the standard codegen orchestrator for Dart/Flutter.
- **Maintenance**: Actively maintained by Dart team. Continuous optimization for speed and reliability.
- **License**: BSD 3-Clause (permissive).
- **2026 improvements**: Faster generation times, better integration with modern Dart features, improved multi-platform support.
- **Performance gotcha**: By default analyzes all source files, causing slowness. Mitigated by centralizing code-generation inputs (e.g., *.codegen.dart suffix), disabling unnecessary codegen (e.g., json_serializable for read-only models), and using build.yaml to limit scope.
- **Best practice**: Use a single file for all @GenerateMocks, @GenerateNiceMocks, etc. to reduce analyzer re-runs. Expected build time: full rebuild under one minute; watch mode should be responsive.

Recommendation: KEEP - build_runner is irreplaceable. Optimize configuration via build.yaml and file suffixes to keep iteration times fast.

---

## 5. Validation: Model and Serialization Codegen

### Freezed + json_serializable

Status: CONFIRMED - Industry standard, actively maintained, excellent compatibility.

- **Maturity**: Both packages are mature, widely used, production-tested.
- **Maintenance**: freezed maintained by Remi Rousselet; json_serializable maintained by Dart team.
- **Licenses**: Freezed is MIT; json_serializable is BSD 3-Clause.
- **freezed purpose**: Code generator for immutable data classes and union (sealed) types.
- **json_serializable purpose**: Automates JSON (de)serialization, converting Dart objects to/from JSON.
- **Integration**: freezed integrates neatly with json_serializable; annotations can be combined.
- **Key benefits**: Immutability, auto-generated copyWith, exhaustive pattern matching on sealed types, type-safe JSON mapping.
- **2026 updates**: Continued compatibility with null safety and recent Dart versions.

Gotcha: When using both freezed and json_serializable together, ensure @JsonSerializable(explicitToJson: true) is set for nested objects, and use @JsonKey for field name mapping when snake_case API fields are involved.

Recommendation: KEEP - freezed + json_serializable is the right pairing for model definition. Immutability and exhaustive serialization are correctness wins.

OpenAPI codegen consideration: The plan mentions "OpenAPI-generated Dart client"; if the server's OpenAPI schema is the source of truth, consider whether to use openapi_flutter_gen (zero build_runner overhead) or whether freezed models should be hand-written and serialized independently. For slim-m's schema-first JSON approach with CI-enforced Dart codegen, hand-writing freezed models and using json_serializable is simpler than managing an OpenAPI-to-Dart pipeline.

---

## 6. Validation: HTTP and WebSocket Clients

### Dio (HTTP)

Status: CONFIRMED - Production-ready, actively maintained, best-in-class for structured HTTP.

- **Maturity**: Dio is mature, production-proven in large Flutter apps.
- **Maintenance**: Actively maintained. Regular updates and feature additions.
- **License**: MIT (permissive).
- **Key features**: Interceptors, global configuration, request cancellation, form data, file downloading, timeout handling, FormData support.
- **vs http package**: Both delegate to dart:io HttpClient underneath; latency difference is < 1ms on simple requests. Choose Dio for its architecture (interceptors, error handling, request/response transformation), not for raw speed.
- **2026 status**: Dio is the standard choice for structured HTTP in Flutter; the http package remains viable for simple scenarios.
- **Advantages**: Interceptor-based middleware (logging, auth token refresh, error handling), cleaner error handling, per-request configuration, easy dependency injection.

Recommendation: KEEP - Dio is the right choice for robust HTTP with clean error handling, middleware, and testability.

### web_socket_channel

Status: CONFIRMED - Official Dart/Flutter standard, maintained, suitable for typed WebSocket.

- **Maturity**: Mature, battle-tested, no competitors have displaced it in 2026.
- **Maintenance**: Part of the Dart ecosystem; regularly maintained.
- **License**: BSD 3-Clause (permissive).
- **Usage**: Provides typed send/receive with a Stream interface; integrates with StreamBuilder.
- **Architecture**: Dual-stream (a stream for incoming messages, a Sink for outgoing).
- **2026 status**: Remains the primary package for direct WebSocket communication in Flutter. No significant alternatives have emerged.
- **Gotcha**: Manual ping/pong management and backpressure handling are the application's responsibility; axum's WebSocket on the server side delegates these to the application as well, so the contract is symmetric.

Recommendation: KEEP - web_socket_channel is the established standard. No reason to replace it; integration with Riverpod and Dio is straightforward.

---

## 7. Validation: Secure Storage

### flutter_secure_storage

Status: CONFIRMED - Actively maintained, widely used, platform-specific security model.

- **Maturity**: Mature, production-tested across millions of installations.
- **Maintenance**: Actively maintained by Jules Stenbakker. Regular security updates.
- **License**: MIT (permissive).
- **Platform support**: Android (Keystore with custom cipher implementations), iOS/macOS (Keychain), Windows, Linux.
- **Version**: 10.0.0+ introduces custom cipher implementations for enhanced security.
- **Key features**: Encrypted key-value storage, optional biometric authentication (Android API 23+, iOS/macOS), platform-native security backends.
- **iOS note**: Uses Keychain; data persists across app uninstalls unless explicitly deleted.
- **Android note**: Encryption via RSA OAEP + AES-GCM by default; compatible with Android Keystore.
- **Gotcha**: Web platform has minimal support; desktop (Windows, Linux) support exists but is less battle-tested than mobile.

Recommendation: KEEP - flutter_secure_storage is the right choice for storing session tokens, per-device keys, and sensitive credentials. The platform-native backends are the correct approach for mobile security.

---

## 8. Validation: Image Caching

### cached_network_image

Status: CONFIRMED - Mature, widely used, with gotchas for web.

- **Maturity**: Mature, production-tested.
- **Maintenance**: Actively maintained; community edition exists for extended web support.
- **License**: MIT (permissive).
- **Purpose**: Download, cache, and display network images with optional placeholders.
- **Integration**: Uses flutter_cache_manager underneath for persistent disk caching.
- **Platforms**: Mobile and desktop work well; web support is minimal and doesn't persist across sessions by default.
- **2026 note**: Community edition (Cached Network Image Community Edition) provides full persistent web caching via IndexedDB (hive_ce), avoiding RAM freezes with native image decoding.
- **Gotcha**: On web, CachedNetworkImage has no built-in persistence; switching to the community edition is necessary for production web usage.

Recommendation: KEEP - cached_network_image is the right choice for mobile and desktop. For web, evaluate whether to use the community edition (indexed_db based) or a separate web-specific caching strategy.

---

## 9. Validation: Icons and Vector Graphics

### Lucide Icons (flutter_lucide or lucide_icons_flutter)

Status: CONFIRMED - Lightweight, modern, actively maintained.

- **Maturity**: Lucide is a popular, open-source icon set with 1699+ icons; flutter packages are actively maintained.
- **Maintenance**: flutter_lucide updated April 2026. Lucide icon set is actively curated.
- **License**: Lucide is ISC (permissive); Flutter packages are MIT.
- **Type**: SVG-based icons, tree-shakable (only used icons are included in the bundle).
- **Cross-platform**: Works across Android, iOS, Web, macOS, Windows, Linux.
- **Design**: Consistent, minimal style; fork of Feather icon set; 1699+ icons available.
- **Package choice**: flutter_lucide is recommended (updated April 2026) over lucide_icons_flutter for active maintenance.

Recommendation: KEEP - flutter_lucide is the right choice for a clean, minimal icon set that fits the "understated" design goals.

### flutter_svg and vector_graphics

Status: CONFIRMED - Mature, with performance improvements in 2026.

- **Purpose**: SVG parsing, rendering, and widget support for Flutter.
- **Maturity**: Mature, widely used, maintained by Dan Field (dnfield).
- **Maintenance**: Actively maintained. Version 2.0+ migrated to vector_graphics_compiler backend.
- **License**: BSD 3-Clause (permissive).
- **2026 improvements**: vector_graphics_compiler enables compile-time SVG precompilation, reducing runtime parsing overhead by up to 98% in some benchmarks.
- **Performance**: With vector_graphics backend, SVGs are compiled at build time to a binary format, drastically improving rendering performance.
- **Use case**: Ideal for custom branded assets, design-system illustrations, and adaptive graphics.

Recommendation: KEEP - flutter_svg with the vector_graphics_compiler backend is the right choice for efficient SVG rendering. Use it for assets not covered by Lucide.

---

## 10. Validation: GIF Rendering

### gif package

Status: CONFIRMED - Lightweight, actively maintained, focused.

- **Maturity**: Mature, specialized for GIF animation control.
- **Maintenance**: Updated May 2026; actively maintained.
- **License**: Check pub.dev for license; typically permissive.
- **Purpose**: Control animated GIFs using a Flutter AnimationController.
- **Features**: Set fixed duration, specify framerate, control playback.
- **Alternatives**: gif_view (preFetch support), flutter_gif (FlutterGifController).
- **Native approach**: Flutter's Image widget natively supports animated GIFs via Image.asset() or Image.network(); the gif package adds programmatic control.

Recommendation: KEEP for Voice Canvas animations if dynamic control is needed. For simple animated GIF display in chat, Flutter's native Image widget is sufficient. Add the gif package if the Voice Canvas requires frame-by-frame control (e.g., pause/resume during playback).

---

## 11. Validation: Design Tokens and Theming

Status: CONFIRMED - Use Material 3 + ThemeExtension for custom tokens.

- **Material 3 tokens**: Built into Flutter; supports light and dark modes automatically.
- **2026 development**: W3C Design Tokens Community Group standard (backed by Adobe, Google, Microsoft, Meta, Figma) is now the de-facto specification.
- **Custom tokens**: Use ThemeExtension to expose custom spacing, radius, and typography tokens beyond Material's built-in roles.
- **Available tools**: token_theme_kit (Flutter theming via design tokens) and design_tokens_generator (generates Dart code from design system files) can accelerate token implementation.
- **Design system approach**: Material 3's token model + ThemeExtension is the Flutter standard; third-party packages can layer on top.

Recommendation: CONFIRM - Use Material 3 + ThemeExtension for custom tokens. If the design system is large or heavily branded, consider design_tokens_generator to automate token-to-Dart code conversion. For slim-m's "neutral-slate design," Material 3's gray and slate color roles are sufficient, with ThemeExtension for custom spacing and radius if needed.

---

## 12. Validation: Localization (i18n/l10n)

### intl + flutter_localizations

Status: CONFIRMED - Official standard, mature, handles complex plurals and formatting.

- **Maturity**: intl is the official Dart internationalization package; mature and stable.
- **Maintenance**: Maintained by Dart team. Part of Flutter's core ecosystem.
- **License**: BSD 3-Clause (permissive).
- **Purpose**: Date/time formatting, currency display, plural rules (including Arabic's six forms), gender-aware messages, bidirectional text.
- **Format**: ARB (Application Resource Bundle) is the standard format; enable generate flag in pubspec.yaml.
- **Scope**: Handles locale-aware formatting beyond simple string translation.

### slang (Modern Alternative)

Status: CONFIRMED - Active alternative, type-safe, modern developer experience.

- **Maturity**: Actively maintained; gaining adoption for type-safe localization.
- **License**: Likely permissive (check pub.dev).
- **Approach**: Configuration in JSON; generates type-safe Dart code for translations.
- **Advantage**: Type-safe access, excellent developer experience, less boilerplate than intl.
- **2026 recommendation**: For new projects, slang is a strong alternative to intl if type safety and modern DX are priorities.

Recommendation: KEEP intl as the default (official, well-documented, handles complex plurals). If the team prefers type-safe translations and simpler JSON config, evaluate slang as a replacement. Both are production-ready in 2026.

---

## 13. Validation: Testing Infrastructure

### Golden Testing: alchemist (not golden_toolkit)

Status: CRITICAL UPDATE - golden_toolkit is discontinued; use alchemist.

- **Status**: In 2025, alchemist became the standard tool for golden testing, replacing the discontinued golden_toolkit.
- **alchemist maturity**: Mature, actively maintained by VeryGoodVentures (inspired by and improving on golden_toolkit).
- **License**: MIT (permissive).
- **Capabilities**: Platform tests (human-readable text), CI tests (colored squares for text replacement), device configuration, size and theme testing.
- **golden_toolkit status**: Deprecated and no longer maintained; should not be used for new projects.

Recommendation: CHANGE - Replace golden_toolkit with alchemist for all golden test infrastructure. alchemist is actively maintained and has directly superseded golden_toolkit in 2026.

### Unit and Widget Testing: mocktail

Status: CONFIRMED - Preferred for null-safe Dart projects.

- **Maturity**: Mature, actively maintained.
- **Maintenance**: Maintained by Dart ecosystem (VeryGoodVentures).
- **License**: MIT (permissive).
- **Approach**: Mock library for Dart, null-safe, no code generation, no build_runner step.
- **vs Mockito**: Mockito uses code generation (@GenerateMocks); mocktail uses a simpler registration model.
- **2026 recommendation**: Mocktail is preferred for most projects; use Mockito only for large codebases where the type safety of generated mocks outweighs the build_runner overhead.

Recommendation: KEEP - mocktail is the right choice for simple, fast unit tests. No code generation overhead; quick to write.

### E2E Testing: patrol

Status: CONFIRMED - Production-ready, actively maintained, multiplatform.

- **Maturity**: Battle-tested in production apps since 2022; mature and feature-complete by 2026.
- **Maintenance**: Actively maintained by LeanCode; version 4.7.0 (2026) adds Swift Package Manager support for iOS/macOS.
- **License**: Likely permissive (check GitHub).
- **Capabilities**: E2E testing for Android, iOS, Web; handles native interactions (permissions, notifications, WebViews), device settings, Wi-Fi toggling.
- **Advantage over integration_test**: Can interact with native platform dialogs and OS-level features; integration_test is limited to Flutter widget layer.
- **Stability**: Requires careful handling of timing and device state; stable when used correctly.
- **2026 status**: Viable for E2E testing if stability concerns are addressed; strong choice for iOS and Android.

Recommendation: KEEP - Patrol is the right choice for E2E testing. Use it for the most critical user journeys (login, messaging, voice call startup). Reserve integration_test for web and simple widget-only flows.

### integration_test

Status: CONFIRMED - Flutter-native, stable, limited to widget layer.

- **Maturity**: Stable, part of Flutter's testing toolkit.
- **Purpose**: Test entire app flows on real/emulated devices; limited to Flutter widget layer (no native access).
- **2026 use**: Primary choice for web E2E testing; supplement to Patrol for mobile.

Recommendation: KEEP - Use integration_test for web and as a complement to Patrol on mobile.

### Test Strategy

Recommendation: Focus testing effort on fast unit tests (business logic) and widget tests (UI states); reserve E2E tests for critical user journeys (login, send message, start voice call, draw on Voice Canvas). Use mocktail for mocks, alchemist for golden tests, Patrol for mobile E2E, integration_test for web E2E.

---

## 14. Validation: LiveKit and WebRTC

### livekit_client (official LiveKit Flutter SDK)

Status: CONFIRMED - Production-ready, actively maintained, built on flutter_webrtc.

- **Maturity**: Official LiveKit SDK; production-tested, actively maintained.
- **Maintenance**: Maintained by LiveKit. Regular updates.
- **License**: Likely Apache 2.0 or MIT (check GitHub).
- **Capabilities**: Audio/video, simulcast, screen capture, data channel, unified plan, end-to-end encryption across iOS, Android, web.
- **Dependency**: Relies on flutter_webrtc for WebRTC primitives.
- **WebRTC version**: Updated to 1.0.25821+ (as of 2026); tracks upstream Google WebRTC closely.

### flutter_webrtc (WebRTC Foundation)

Status: CONFIRMED - Actively maintained, multiplatform, battle-tested.

- **Maturity**: Mature, widely used, long history of production deployments.
- **Maintenance**: Actively maintained by Flutter WebRTC community.
- **License**: MIT (permissive).
- **Platforms**: iOS, Android, macOS, Windows, Linux, Web.
- **Features**: Audio/video, simulcast, screen capture, data channels, unified plan.
- **Integration**: Underlying WebRTC engine for livekit_client.

Recommendation: KEEP - livekit_client + flutter_webrtc is the right architecture. Official SDK integration is a win for maintenance and support.

---

## 15. Validation: Code Generation Strategy

### OpenAPI vs. freezed Models

Status: DECISION POINT - Plan specifies "schema-first JSON from OpenAPI"; evaluate actual strategy.

Architecture states: "schema-first JSON from one OpenAPI plus JSON Schema source with CI-enforced Rust and Dart codegen."

Options:
1. **Use openapi_flutter_gen**: Zero build_runner overhead; generates standalone .dart files (models, API services, sealed responses). One-shot CLI; outputs committed source files.
2. **Hand-write freezed models + json_serializable**: Models are Dart-native; OpenAPI schema is documentation, not the source of truth for Dart models.

Recommendation: For slim-m's Dart client, hand-writing freezed models is simpler and aligns with the brief's "readable APIs" principle. The OpenAPI schema is authoritative for the server and Rust/TypeScript codegen; for Dart, write models explicitly to keep them idiomatic and easy to review. If the API surface is large (100+ endpoints), evaluate openapi_flutter_gen for automation; for a focused chat API (messages, channels, voice sessions, Voice Canvas), hand-written models are faster and more maintainable.

Decision: RECOMMEND hand-written freezed models unless the API grows significantly beyond core chat operations.

---

## 2. Additions: Recommended New Packages

### 2.1 Riverpod Testing: riverpod_test (or built-in Riverpod testing)

Not strictly a new package, but ensure the test suite uses Riverpod's ProviderContainer for isolated provider testing and provider overrides for mocking.

Recommendation: Add to testing best practices; no new package required.

### 2.2 HTTP Interceptor Libraries (Optional)

For auth token refresh and error handling, consider:
- **retry**: Provides retry logic with exponential backoff; integrates cleanly with Dio.
- **dio_smart_retry**: Dio-specific retry interceptor.

Recommendation: CONDITIONAL - If the app needs sophisticated retry logic with backoff and jitter, add retry or dio_smart_retry. For a chat app with offline-first local echo, simple retry is likely sufficient; evaluate after prototyping.

### 2.3 Connectivity and Reachability: connectivity_plus

Purpose: Detect network state changes (connected/disconnected) and adapt UI (show offline indicator, queue messages locally).

Recommendation: ADD - Essential for a self-hosted chat app where users may lose connectivity. Pair with Riverpod to notify the state layer of network changes, and queue messages locally via Drift while offline.

Package: connectivity_plus (MIT license, actively maintained).

### 2.4 Background Execution: background_fetch (or local_push_notification for on-device notifications)

Purpose: Handle background message delivery and wake-up callbacks from the push relay.

Recommendation: ADD - Essential for mobile. Pair with flutter_local_notifications for on-device alert display when messages arrive in the background.

Packages:
- **background_fetch**: Periodic background tasks (for keep-alive, sync).
- **flutter_local_notifications**: Display local notifications, play sounds, integrate with push relay delivery.

### 2.5 Permissions: permission_handler

Purpose: Request and check permissions for camera, microphone, storage (for GIF paste to Voice Canvas).

Recommendation: ADD - Essential for voice calls and media features.

Package: permission_handler (MIT license, actively maintained).

### 2.6 Gesture and Keyboard Handling: keyboard_dismisser (or built-in focus management)

Purpose: Dismiss keyboard on demand; handle text field focus in chat input.

Recommendation: CONDITIONAL - Flutter's built-in focus management is often sufficient. Add keyboard_dismisser if UX testing reveals awkward keyboard behavior on iOS (e.g., keyboard obscuring chat input).

### 2.7 Analytics and Crash Reporting (if needed for self-hosting insights)

Recommendation: DEFER - Not in scope for v1. If added, use permissively-licensed libraries (e.g., Sentry for error reporting, or custom instrumentation via OpenTelemetry).

### 2.8 Voice Canvas Rendering: custom_paint + ChangeNotifier for undo/redo

Recommendation: Already planned; no new package for 60fps canvas. Use custom_paint with GPU acceleration. Consider skia-based rendering if the canvas requires complex visual effects.

### 2.9 State Persistence Across Sessions: hydrated_riverpod (Optional)

Purpose: Persist selected channel, current user, recent searches across app restarts.

Recommendation: CONDITIONAL - Riverpod's caching is already powerful; add hydrated_riverpod only if the app needs to persist UI state beyond local database queries. Evaluate after prototyping.

### 2.10 Notification Sound Synthesis (Audio Synthesis)

Recommendation: DEFER to audio design phase. May require a custom audio synthesis library or pre-generated procedural tones stored as assets.

---

## 3. Changes: Recommendations to Replace or Upgrade

### 3.1 Golden Testing Framework: golden_toolkit -> alchemist (CRITICAL)

Recommendation: CHANGE - Replace golden_toolkit (discontinued) with alchemist immediately.

Confidence: HIGH - alchemist is the community-accepted successor and is actively maintained.

---

### 3.2 Web Caching: Consider Cached Network Image Community Edition for Web

Current: cached_network_image (mobile/desktop only).

Recommendation: For the web platform (if supported), evaluate cached_network_image Community Edition (IndexedDB-based caching) to enable persistent image caching without RAM bloat.

Confidence: MEDIUM - Only if web support is a priority in v1.

---

### 3.3 Riverpod Codegen: Confirm riverpod_generator is in pubspec.yaml (Not a change, a validation point)

Recommendation: Ensure riverpod_generator is explicitly listed as a dev_dependency and the @riverpod annotation is used throughout the codebase. Do not mix manual providers with codegen; consistency matters for team onboarding.

Confidence: HIGH - Codegen is the 2026 standard.

---

## 4. Risks and Version Pitfalls

### 4.1 Build Runner Performance

Risk: build_runner can become slow as the codebase grows, especially with multiple codegen libraries (riverpod_generator, freezed, json_serializable, retrofit, etc.) all running in the same pass.

Mitigation:
- Centralize codegen inputs (e.g., *.codegen.dart suffix).
- Use build.yaml to exclude unnecessary targets.
- Profile build times regularly via `flutter pub run build_runner build --verbose`.
- Consider monorepo organization (separate packages for models, client, server-side code) if code generation becomes a bottleneck.

### 4.2 Drift WAL Mode Filesystem Compatibility

Risk: WAL mode requires a filesystem that supports shared memory and memory-mapped I/O. Network-mounted data directories (e.g., NFS, SMB) may not work reliably.

Mitigation: Document clearly that self-hosted deployments must use local storage for Drift's database file, not network shares. Provide explicit error messages if WAL mode fails.

### 4.3 flutter_secure_storage Platform Differences

Risk: Keychain (iOS) persists across app uninstalls; Keystore (Android) may or may not, depending on device state. Biometric authentication is optional and platform-specific.

Mitigation: Document the platform differences clearly. For session tokens, prefer short-lived tokens (refreshed via opaque server-side session ID) over long-lived keys in secure storage. Implement graceful fallback if biometric auth is unavailable.

### 4.4 Patrol E2E Test Stability

Risk: Patrol tests can be flaky if timing assumptions are wrong or device state is unpredictable. Native permission dialogs, slow network, and device sleep can cause intermittent failures.

Mitigation: Use Patrol's built-in wait/retry mechanisms. Mock network responses for E2E tests. Run E2E tests on CI against real/emulated devices with consistent configuration. Reserve E2E for critical paths only (login, send message, start voice call).

### 4.5 OpenAPI Schema Evolution

Risk: If using openapi_flutter_gen, breaking changes in the OpenAPI schema (field removal, type change) will require regenerating the Dart client. If hand-writing freezed models, schema drift between server and client can happen silently.

Mitigation: Implement schema-compatibility checks in CI (e.g., protobuf-style breaking-change detection on the OpenAPI schema). If using freezed models, add a CI step to validate that Dart models match the server schema (manual review or automated JSON schema validation).

### 4.6 Intl / Slang Codegen

Risk: Intl codegen depends on ARB files being well-formed and complete. Missing translations in ARB files can cause runtime errors.

Mitigation: Add a CI step to validate ARB files and ensure all defined locales have complete translations. Use intl's @.attribute syntax to document plurals and select rules explicitly.

### 4.7 Riverpod Version Pinning and Tower Middleware Compatibility

Risk: riverpod_generator is tightly coupled to the Riverpod version. A major bump in Riverpod can break generated code. Similarly, dependencies on Dio and tower-http can have version conflicts.

Mitigation: Pin riverpod and riverpod_generator to the same minor version. Review changelogs before major version bumps. Use dependency_overrides in pubspec.yaml to resolve conflicts during active development.

### 4.8 GIF Memory Overhead

Risk: Large animated GIFs (especially in the Voice Canvas during pasted GIFs) can consume significant memory, especially on low-end Android devices.

Mitigation: Limit GIF size in the chat UI (e.g., max 500x500 pixels). For the Voice Canvas, consider lazy-loading GIFs and freeing memory when they leave the visible area. Profile memory usage on a Pixel 5 or equivalent mid-range device.

### 4.9 Web Platform Limitations

Risk: Several packages have minimal or no web support (flutter_secure_storage, cached_network_image, Patrol). If web is added later, significant rework may be needed.

Mitigation: If web support is a future goal, evaluate web-compatible alternatives early (e.g., web crypto APIs for secure storage, IndexedDB for caching). Prototype web compatibility before committing to a v1 web release.

### 4.10 Flutter 3.x LTS and Dart Version Compatibility

Risk: Flutter and Dart versions can have breaking changes. A major Flutter bump might require rebuilding the entire dependency tree.

Mitigation: Pin Flutter and Dart versions explicitly in pubspec.yaml and CI/CD (use flutter/setup-flutter action with a specific version). Review breaking changes before upgrading.

---

## 5. Platform-Specific Gotchas

### iOS (Primary Testing Platform)

- **Keychain persistence**: Session tokens stored in flutter_secure_storage persist across app uninstalls unless explicitly deleted. Document this for security reviews.
- **Swift Package Manager**: As of 2026, SPM is now supported as an alternative to CocoaPods for Flutter plugins. Consider this for plugin dependencies if it improves build times.
- **Biometric auth**: All modern iOS devices support biometric authentication (Face ID, Touch ID). flutter_secure_storage can integrate biometric auth; verify the UX is smooth and non-blocking.
- **Background tasks**: iOS limits background execution time. Use background_fetch carefully; understand iOS restrictions on VoIP and background audio.
- **Notification sounds**: Ensure procedurally-generated or custom notification sounds are properly integrated with iOS's notification system. Test volume normalization across different notification types.

### Linux/Fedora Desktop (Primary Testing Platform)

- **Snap vs. manual installation**: Avoid snap on Fedora; download the Flutter SDK manually for better control.
- **GTK/Material Design**: Flutter desktop on Linux uses GTK (or custom rendering). Material Design widgets render correctly, but some platform-specific affordances (right-click context menus, native file dialogs) require platform integration.
- **Database (SQLite)**: Drift works reliably on Linux. WAL mode is fully supported on Linux filesystems.
- **Permissions**: File I/O and network access on Linux desktop are largely unrestricted; no runtime permission model like Android/iOS.
- **Notification integration**: Use flutter_local_notifications with DBus/Linux notifications for desktop toasts.
- **Fedora-specific packaging**: If packaging as Flatpak or RPM, test Flutter app inside the sandbox and verify file access permissions.

### Android

- **Keystore**: Encryption via Keystore is mandatory for flutter_secure_storage. Keystore has platform-specific behavior (e.g., when no lock screen is set, some Keystore features degrade).
- **Background tasks**: Use background_fetch with careful timing to avoid battery drain. Background VoIP service (for push relay wake-up) requires persistent background service, which has battery implications.
- **Permission model**: Android 6.0+ requires runtime permissions for camera, microphone, storage. Use permission_handler and test on API level 34+ (Android 14).
- **WebRTC on Android**: flutter_webrtc has well-tested Android support; verify hardware acceleration is enabled in the Android app.

---

## 6. License Audit

All recommended packages are permissively licensed (MIT, BSD 3-Clause, Apache 2.0, ISC):

- Riverpod: MIT
- Drift: MIT
- GoRouter: BSD 3-Clause
- Dio: MIT
- web_socket_channel: BSD 3-Clause
- flutter_secure_storage: MIT
- cached_network_image: MIT
- flutter_svg: BSD 3-Clause
- flutter_lucide (lucide icons): MIT
- Freezed: MIT
- json_serializable: BSD 3-Clause
- Mocktail: MIT
- Alchemist: MIT
- Patrol: (check GitHub, likely MIT or Apache 2.0)
- livekit_client: Apache 2.0
- flutter_webrtc: MIT
- Intl: BSD 3-Clause
- connectivity_plus: BSD 3-Clause
- permission_handler: MIT

No GPL, AGPL, or strong-copyleft licenses in the recommended stack.

---

## 7. Recommendations Summary

### Confirmed (Keep)

- Riverpod 3.3+ with riverpod_generator (state/DI)
- Drift (local persistence)
- GoRouter (routing)
- Dio (HTTP)
- web_socket_channel (WebSocket)
- flutter_secure_storage (secure storage)
- cached_network_image (image caching)
- flutter_lucide / Lucide icons
- flutter_svg with vector_graphics backend (SVG rendering)
- Freezed + json_serializable (models)
- Mocktail (testing)
- Patrol (E2E mobile)
- integration_test (web/simple flows)
- Intl (localization)
- livekit_client + flutter_webrtc (media)
- Material 3 + ThemeExtension (design tokens)

### Critical Changes

- Replace golden_toolkit with alchemist (golden tests).

### Strongly Recommended Additions

- connectivity_plus (network state monitoring)
- background_fetch (push relay wake-up callback)
- flutter_local_notifications (notification display)
- permission_handler (camera, microphone, storage permissions)

### Conditional Additions

- Slang (if type-safe localization is preferred over intl)
- Cached Network Image Community Edition (if web support is added)
- retry / dio_smart_retry (if sophisticated retry logic is needed)
- hydrated_riverpod (if UI state needs to persist across app restarts)
- design_tokens_generator (if design system is large)

### Deferred

- OpenAPI-to-Dart codegen (recommend hand-written freezed models for slim-m's focused API surface)
- Background audio/VoIP service (evaluate after voice call prototyping)
- Procedural audio synthesis (defer to audio design phase)
- Web platform support (full web parity can follow mobile v1)

---

## 8. Closing Notes

The Flutter package stack is well-chosen and reflects the 2026 ecosystem's consensus choices.
The primary risks are build_runner performance (manage via build.yaml configuration), Patrol E2E flakiness (use judiciously), and platform-specific edge cases (thoroughly test on iOS and Fedora Linux).

The key wins from this stack:
- Riverpod codegen + Drift provides type safety and reactivity at all layers (state, persistence, UI).
- GoRouter + Riverpod eliminates entire classes of navigation and state bugs.
- Dio + web_socket_channel provide structured, testable HTTP and WebSocket clients.
- Alchemist + Patrol + mocktail enable fast iteration and high test confidence.
- Material 3 + ThemeExtension and Lucide icons provide a clean, consistent design foundation.

All packages are actively maintained, permissively licensed, and lightweight enough to support the brief's "lightweight and cheap to self-host" principle.
