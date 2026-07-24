# Media and Voice Canvas Stack Validation

Date: July 2026
Region: Real-time media and collaborative voice canvas rendering

This validation confirms library and tooling choices for the media streaming, real-time WebRTC, and infinite collaborative voice canvas.
It identifies maturity, maintenance status, licenses, gotchas, and recommends improvements against the project's lightweight and maintainability priorities.

## Executive Summary

The planned stack is solid for iOS and Android mobile clients, with Impeller-backed CustomPainter canvas rendering, Riverpod state management, and Drift local storage all confirmed as best-in-class 2026 choices.
However, Linux desktop WebRTC and media capture present a significant risk gap: neither flutter_webrtc's PipeWire/Wayland support nor livekit_client has Linux desktop support in production form.
The solution requires using LiveKit C++ SDK via FFI for Linux or investing in XDG Desktop Portal integration.
Canvas operation logging, multi-user conflict resolution, and scale testing for many simultaneous GIFs and images need early design work.

## Real-Time Media: Voice and Video

### livekit_client (Official LiveKit Flutter SDK)

**Status**: Production-ready, actively maintained.

**Current Version**: 2.8.1 stable, 2.9.0-dev.0 (updated within 30 days as of July 2026).

**Platforms**: iOS, Android, Web.

**Maintenance**: Regular updates, responsive to issues.

**License**: Apache 2.0 (permissive).

**Key Features**:
- Native audio/video capture and rendering.
- Simulcast and bandwidth adaptation.
- Data channels for side-band communication.
- Official support from LiveKit maintainers.

**Gotchas**:
- No Linux desktop support in the Flutter package.
- Web support is browser-only, not suitable for Flutter Web on desktop.
- Requires native plugin compilation for iOS and Android.

**Verdict**: CONFIRMED for iOS and Android mobile clients.

**FLAG: Linux Desktop Media Capture Unsupported** - The brief specifies Linux (Fedora) as primary desktop testing environment.
The flutter SDK has no Linux support.
For Linux desktop, you must either:
1. Use LiveKit C++ SDK via Dart FFI (adds native binding complexity).
2. Use a separate Go or Rust process for media handling (architectural shift).
3. Delay Linux desktop support until community fork or official port exists.

### flutter_webrtc

**Status**: Production-ready, actively maintained (July 2026).

**Platforms**: iOS, Android, Web, Windows, macOS, Linux.

**Maintenance**: Active development; recent issues reported as of July 1-6, 2026.

**License**: Apache 2.0 (permissive).

**Key Features**:
- Raw WebRTC engine access.
- Screen and window capture on desktop.
- Peer-to-peer data channels.
- Audio/video rendering.

**Known Issues on Linux**:
- **PipeWire/Wayland Screen Capture**: The screenshare dialog crashes on Linux with PipeWire because the library does not await the XDG Desktop Portal prompt response.
  The portal shows a user selection dialog for screen/window/region, but flutter_webrtc does not properly integrate with this async flow.
- The package relies on libwebrtc desktop bindings, which require CMake compilation; binary caching and CI setup add friction.

**Gotchas**:
- Screen capture on modern Linux (Wayland + PipeWire) requires XDG Desktop Portal integration (D-Bus API org.freedesktop.portal.ScreenCast).
- PipeWire streams are handed back as D-Bus file descriptors, requiring careful resource management.
- The flutter_webrtc bindings for Linux do not currently wrap this portal logic.

**Verdict**: CONFIRMED for iOS, Android, Web, Windows, macOS.

**HIGH-RISK FLAG: Linux Screen Capture** - PipeWire/Wayland screen capture is broken in current builds.
You need either:
1. Contribute a fix to flutter_webrtc to integrate XDG Desktop Portal (non-trivial C++ binding work).
2. Use a custom native wrapper or helper service for screen capture on Linux (Go or Rust).
3. Document that Linux desktop screen sharing is not yet supported and target it for later release.

### LiveKit C++ SDK (Alternative for Linux Desktop)

**Status**: Officially supported, actively maintained.

**Platforms**: Linux (x86-64 and ARM: Jetson, Raspberry Pi, Rockchip), macOS, Windows.

**Build System**: CMake-first (native integration, not Flutter plugin).

**License**: Apache 2.0 (permissive).

**Key Features**:
- Native C++ real-time media engine.
- Proven on embedded Linux and desktop.
- Full VP8/Opus support matching mobile SDK.

**Integration Path**: Use Dart FFI (ffi package) to call C++ bindings, or spawn a separate process for media handling on Linux.

**Verdict**: CONFIRMED as viable fallback for Linux desktop.

**Note**: This requires Dart FFI bindings (not currently in the spec) or architectural changes to offload media to a separate Rust/Go service.

## Canvas Rendering and Interaction

### Impeller + CustomPainter

**Status**: Impeller is the default Flutter renderer as of 2026 (replaces Skia).

**Rendering Pipeline**: Metal (iOS), Vulkan (Android), Skia fallback (older Android, web).

**Performance Characteristics**:
- Ahead-of-Time (AOT) shader compilation at build time; no runtime jank from new shaders.
- Rasterization is 50% faster than Skia in benchmarks.
- Consistent frame times from the first frame.
- True 120fps capability on flagship devices.

**CustomPainter Optimization**:
- Use RepaintBoundary to isolate repaints and prevent full-screen redraw.
- Cache Paint objects in CustomPainter instances (avoid recreating per-frame).
- Avoid thousands of complex overlapping paths with transparency; Impeller's tessellator can struggle to convert to triangles fast enough, causing stuttering.
- Profile with Flutter DevTools "Performance" tab; target 8.3ms budget per frame at 120fps.

**Gotchas**:
- CustomPaint is still a widget, so parent repaints can trigger child repaints. Use RepaintBoundary wisely.
- For very large canvases (many objects), spatial culling is mandatory.
- Shader-heavy drawing (blurs, glows, custom effects) can still exceed frame budget; prefer simpler primitives.

**Verdict**: CONFIRMED as the right choice for canvas rendering.

**Design Note**: Plan culling and dirty-region rendering early; do not assume CustomPainter alone can handle thousands of simultaneous objects without optimization.

### infinite_canvas (Flutter Package)

**Status**: Stable, last updated August 2024.

**Package**: pub.dev/packages/infinite_canvas.

**Architecture**: Wraps InteractiveViewer with CustomMultiChildLayout to allow widget-based children and drag/select interactions.

**License**: Likely MIT (Hyper Designed project).

**Key Features**:
- Infinite scrolling and zooming.
- Widget children (not custom painting) can be placed on the canvas.
- Drag to move, selection states.
- Gestures handled via gesture arena.

**Limitations**:
- Designed for widget-based layout, not for thousands of custom-drawn objects.
- Does not include collaborative editing or operational transformation.
- No built-in spatial indexing for culling.

**Verdict**: CONFIRMED as a starting point for the canvas structure.

**Note**: You will likely need to extend or replace its culling logic for high-object-count scenarios (many concurrent users drawing).
Plan to implement spatial indexing separately.

### flutter_box_transform

**Status**: Production-ready, actively maintained and well-documented.

**Package**: pub.dev/packages/flutter_box_transform (Hyper Designed project).

**License**: Likely MIT/Apache.

**Key Features**:
- Draggable and resizable boxes with programmatic control.
- Dimension constraints (min/max bounds).
- Flipping mechanics (invert drag direction if resize hits constraints).
- Drag clamping (constrain motion to a bounding region).
- Flexible resizing modes (corner, edge, custom handles).

**Use Cases**: Participant camera bubbles, screen share windows, image/GIF windows on the canvas.

**Verdict**: CONFIRMED for moveable and resizable windows.

**Design Integration**: Use flutter_box_transform for fixed-position elements (camera bubbles, screen shares, images) and CustomPainter for freehand drawing annotations.
This hybrid approach avoids the performance cost of rendering thousands of widgets while preserving interactivity for windows.

### Spatial Indexing (R-tree vs Quadtree)

**r_tree Package**

**Status**: Actively maintained, updated February 2026.

**Package**: pub.dev/packages/r_tree.

**Type**: R-tree data structure for spatial access methods.

**Use Case**: Index and query 2D bounding boxes (participant windows, images, screen shares) for culling and hit detection.

**License**: Likely MIT/Apache.

**Performance**: O(log N) for balanced insertions/queries.

**Verdict**: CONFIRMED, recommended for primary spatial index due to recent maintenance.

**quadtree Package**

**Status**: Stable, last updated September 2024.

**Package**: pub.dev/packages/quadtree.

**Type**: Quadtree for recursive spatial subdivision.

**Use Case**: Fast range queries and collision detection.

**expandable-quadtree-dart (GitHub)**

**Status**: Flexible, expandable quadtree implementation on GitHub.

**Variants**: Expandable, horizontally expandable, vertically expandable.

**Verdict**: CONFIRMED as alternatives, but r_tree is preferred due to recent updates and proven R-tree optimization research.

**Design Decision**: Use r_tree for spatial culling of drawing commands and UI elements on the canvas.
Early profiling on a reference implementation will tell you if hand-rolled is better (unlikely).

### Gesture Recognition: Pan, Zoom, Draw

**Flutter gestures (built-in)**

**Status**: Core Flutter framework, actively maintained.

**Components**:
- PanGestureRecognizer: Detects drag movement.
- ScaleGestureRecognizer: Detects pinch-zoom and rotation.
- TapGestureRecognizer: Detects taps.
- Gesture arena: Disambiguates overlapping recognizers (only one wins per pointer).

**2026 Updates**:
- Trackpad PointerPanZoom events trigger pan/scale callbacks (macOS, Linux, Windows).
- Gesture arena properly handles multi-touch and multi-pointer scenarios.

**Verdict**: CONFIRMED, built-in support is solid.

**Canvas Interaction Model**: Gesture arena ensures that pan+draw, zoom+draw, and select+drag do not interfere.
Build a custom GestureRecognizer that dispatches to the correct canvas handler based on mode (draw vs pan vs select).

### Image Caching: Many On-Canvas Images

**cached_network_image**

**Status**: Popular, actively maintained, but limited web support.

**Package**: pub.dev/packages/cached_network_image.

**Platforms**: iOS, Android, desktop (using flutter_cache_manager).

**Web Support**: Minimal; no persistent caching on the web platform.

**License**: Likely MIT/Apache.

**Issue**: On web, images stay in RAM and are not persisted between sessions.
For a collaborative canvas with many shared images, this can lead to high memory usage.

**Verdict**: CONFIRMED for mobile and desktop, but FLAG for web.

**cached_network_image Community Edition (CE)**

**Status**: Actively maintained fork addressing limitations of the official package.

**Key Improvement**: Full persistent image caching on Web via IndexedDB.

**Benefit**: Avoids RAM freezes by using native image decoding sizes and storing decoded images in IndexedDB.

**License**: Likely MIT/Apache.

**Verdict**: RECOMMENDED for use instead of the official package due to superior web support and memory efficiency.

**Design Note**: Cache images locally with Drift or Isar on mobile, and use cached_network_image CE on web and desktop.
For many simultaneous images on the canvas, prefetch and cache proactively during idle time.

### GIF Playback at Scale

**gif_player Package**

**Status**: Feature-rich, updated April 2026.

**Package**: pub.dev/packages/gif_player.

**Features**:
- Play, pause, seek, progress bar.
- Per-frame control.
- Duration specification or framerate setting.

**License**: Likely MIT.

**Verdict**: CONFIRMED for GIF control if needed.

**gif Package**

**Status**: Stable, simpler alternative.

**Package**: pub.dev/packages/gif.

**Integration**: Control via Flutter AnimationController for timing.

**Verdict**: CONFIRMED, lighter alternative if minimal control needed.

**Scale Concerns**:
- Multiple animated GIFs on the same canvas can cause CPU and battery drain on mobile.
- Each GIF is decoded in memory; test with 5-10 simultaneous GIFs at target device resolution (e.g., 512x512 each).
- Profiling with DevTools' performance overlay is mandatory before declaring canvas GIF support as done.

**Recommendation**: Profile early and set a hard limit on concurrent animated GIFs (e.g., 5 visible at a time); mute or unload off-screen GIFs.

## Backend: Canvas Operations and Event Log

### Axum + Tokio (WebSocket Server)

**Status**: Production-ready, actively maintained, widely used in 2026.

**Framework**: Axum (web framework), Tokio (async runtime).

**WebSocket Support**: Via axum::extract::ws, ergonomic and efficient.

**Performance**: Handles millions of concurrent connections on modest hardware.

**Comparison to Actix Web**:
- Actix Web: 10-15% higher throughput under load, battle-tested on more production systems.
- Axum: Better ergonomics, tighter Tokio integration, modern async trait support, preferred for new projects in 2026.

**License**: MIT/Apache 2.0 (permissive).

**Verdict**: CONFIRMED as the right choice for lightweight WebSocket server.

**Design**: One WebSocket connection per client.
Server broadcasts drawing commands to all participants in a canvas session.
Commands are idempotent (redraw operations, not stateful edits); clients apply in-order via monotonic sequence numbers.

### Canvas Operation Log (Rust Backend)

**Status**: Not a crate; typically hand-rolled as append-only database table.

**Architecture**:
- Store each drawing operation (line, shape, image place, erase, etc.) as a JSON payload in an append-only SQLite table.
- Assign server-side sequence numbers (64-bit monotonic) per-scope to ensure total order.
- Client generates UUIDv7 for local identity and conflict detection.
- On reconnect, client requests all operations since last known sequence; server replays them.

**Serialization**:
- serde (Rust ecosystem standard) for Rust data -> JSON.
- Ensure the JSON schema matches the client-side Dart schema (OpenAPI + JSON Schema codegen).

**Persistence**:
- Append to SQLite with FTS5 full-text search on operation metadata (optional, for audit trails).
- Use SQLite's WAL mode for concurrent reads during writes (single writer, read-only pool).

**Verdict**: CONFIRMED as the right approach; hand-rolled append-only log with compile-time-checked queries via sqlx.

**No Crate Recommendation**: The operation log is specific to your domain (canvas operations, not generic event sourcing); off-the-shelf crates (like eventstore) add unnecessary overhead.
Keep it simple: one table, ordered by sequence, immutable writes.

## State Management and Local Storage (Mobile Client)

### Riverpod

**Status**: Best-in-class state management for Flutter in 2026.

**Version**: 3.0+ with codegen (riverpod_generator).

**Maturity**: Production-ready, actively maintained.

**Performance**:
- 20-25% lower memory usage than Provider in large applications.
- Compile-time safety via provider definitions.
- Lazy initialization and smart caching.

**License**: MIT (permissive).

**Verdict**: CONFIRMED as the right choice.

**Integration with Canvas**: Use Riverpod for canvas session state (current participant list, my user identity, connection status), and let the local Drift store hold canvas operation history for offline replay.

### Drift (SQLite ORM)

**Status**: Production-ready, actively maintained.

**Platforms**: iOS, Android, macOS, Windows, Linux, Web.

**Type-Safety**: Compile-time SQL checking via dart analyzer.

**Features**:
- Reactive queries (StreamBuilder-friendly).
- Migrations with version management.
- Foreign keys and relationships.
- Custom SQL support.

**License**: MIT (permissive).

**Verdict**: CONFIRMED as the right choice for local storage.

**Canvas Use Case**: Store all drawing operations in Drift with a sequence number and creation timestamp.
Replay from last checkpoint on app launch.

### flutter_secure_storage

**Status**: Production-ready, actively maintained (July 2026).

**Platforms**: iOS, Android, macOS, Windows, Linux.

**Security Implementation**:
- iOS: Keychain.
- Android: Encrypted shared preferences or Android Keystore.
- Other: Platform-specific secure mechanisms.

**Optional Biometric Auth**: Supported on Android (API 23+) and iOS/macOS.

**License**: BSD/MIT (permissive).

**Verdict**: CONFIRMED for storing session tokens and per-device keys.

**Note**: This is for small, sensitive items (tokens, encryption keys).
Do not store large data in flutter_secure_storage; use Drift for that.

## UI Navigation and Design

### GoRouter

**Status**: Standard Flutter routing library, actively maintained.

**License**: MIT/Apache 2.0.

**Verdict**: CONFIRMED as the routing choice.

### Lucide Icons

**Status**: Popular icon library with Flutter support.

**License**: ISC (permissive).

**Design Fit**: Neutral, minimal aesthetic matches the brief's "understated, clean, practical" preference.

**Verdict**: CONFIRMED for icon library.

## Additions: Libraries and Tools to Add

### 1. r_tree Package (Explicit Dependency)

**Name**: r_tree (pub.dev/packages/r_tree).

**Version**: Latest (updated February 2026).

**Purpose**: Spatial indexing for canvas culling and hit detection.

**Why**: Reduces rendering cost by skipping off-screen objects.
Enables efficient collision detection for gesture interactions on a densely-populated canvas.

**Fit**: Lightweight, single-purpose, no heavy dependencies.

**Priority**: HIGH - Add early to avoid rendering performance issues at scale.

### 2. cached_network_image Community Edition (Replace Official)

**Name**: cached_network_image (community edition).

**Package URL**: pub.dev/packages/cached_network_image (use the CE fork or check for official merge).

**Purpose**: High-performance image caching with full web support.

**Why**: The official package lacks persistent web caching; the CE fork uses IndexedDB, preventing RAM bloat and cache loss on page refresh.

**Fit**: Lightweight, drop-in replacement for image caching on web and desktop.

**Priority**: MEDIUM - Add before scaling to many images on canvas.

### 3. gif_player Package (Optional, Recommended)

**Name**: gif_player (pub.dev/packages/gif_player).

**Version**: Latest (updated April 2026).

**Purpose**: Full-featured GIF animation control (play, pause, seek, progress).

**Why**: If the canvas needs to support user-initiated GIF controls (pause for annotation, skip frames), gif_player provides these natively.
Simpler than building custom controls.

**Fit**: Single-purpose, low overhead.

**Priority**: MEDIUM - Add if GIF interaction is a canvas feature; skip if GIFs are fire-and-forget animations.

### 4. Dart FFI Bindings to LiveKit C++ SDK (For Linux Desktop)

**Purpose**: Enable media capture and rendering on Linux desktop.

**What to Add**: A Dart package that wraps LiveKit C++ SDK via ffi (foreign function interface).

**Scope**: Non-trivial; requires C++ knowledge, CMake integration, and platform-specific debugging.

**Why**: flutter_webrtc and livekit_client both lack production Linux desktop support.
Using the C++ SDK via FFI keeps media handling in-process and avoids spawning a separate service.

**Fit**: Fits the lightweight self-hosting goal; eliminates external media service dependencies.

**Priority**: HIGH - Required for Linux desktop support; otherwise, document Linux desktop as out-of-scope for the 1.0 release.

### 5. XDG Desktop Portal Wrapper (For Linux Screen Sharing)

**Purpose**: Enable screen and window capture on Linux (Wayland + PipeWire).

**Scope**: Custom Dart/Rust wrapper around org.freedesktop.portal.ScreenCast (D-Bus API).

**Why**: flutter_webrtc does not currently integrate with the XDG Desktop Portal.
A wrapper handles the async portal dialog and returns a PipeWire stream that flutter_webrtc can consume.

**Fit**: Lightweight, single-purpose, Linux-only.

**Priority**: MEDIUM - Recommend for Linux desktop 1.1 or 2.0; mark as unimplemented for 1.0 if prioritizing iOS/Android.

## Changes: Recommendations to Swap or Adjust

### Change 1: Canvas Drawing and Object Management

**Current Approach (Implied)**: Assume all canvas objects (drawings, images, windows) are rendered by CustomPainter or flutter_box_transform.

**Proposed Adjustment**: Use a hybrid model:
- **CustomPainter for freehand annotations and vector shapes**: Leverages Impeller's tessellation and shader compilation.
- **flutter_box_transform for fixed-position interactive elements**: Camera bubbles, screen shares, pasted images/GIFs.
- **Spatial Index (r_tree) for culling**: Skip drawing objects outside the visible viewport.

**Why**: Separates concerns, allows independent optimization, and reduces CPU cost of rendering many objects.

**Confidence**: HIGH - This is the standard approach in production canvas applications (e.g., Figma, Miro).

### Change 2: Linux Desktop Media Architecture

**Current Approach (Implied)**: Use livekit_client and flutter_webrtc uniformly across all platforms.

**Proposed Alternative**: For Linux Desktop, use one of the following:
1. **Option A (Recommended)**: LiveKit C++ SDK via Dart FFI for media, flutter_webrtc for WebRTC signaling only.
2. **Option B (If FFI binding is too complex)**: Spawn a separate media helper process (Go or Rust) that talks to the main Dart app via local sockets.
3. **Option C (Defer)**: Document Linux desktop as a post-1.0 feature and focus 1.0 on iOS/Android.

**Why**: Neither flutter SDK has production Linux desktop support; using the C++ SDK sidesteps this limitation.

**Confidence**: HIGH for Option C (deferral), MEDIUM for Options A and B (require implementation effort).

### Change 3: Canvas Operation Conflict Resolution

**Current Approach (Implied)**: Rely on server-side sequence numbers to ensure total order.

**Proposed Approach**: Layer in Operational Transformation (OT) or CRDT (Conflict-free Replicated Data Type) principles:
- Client-generatable UUIDv7 for operation identity (already in spec).
- Server-assigned sequence per-scope (already in spec).
- On conflict (e.g., two users draw on the same pixel), use a deterministic tiebreaker: compare UUIDs lexicographically, or use timestamp + user ID.

**Why**: Ensures that all clients converge to the same canvas state, even under network delays and reordering.

**Implementation**: Keep the current append-only log; add a deterministic conflict-resolution rule in the client.

**Confidence**: HIGH - This is well-researched and proven in collaborative editors; design early, do not add post-1.0.

## Risks and Version Pitfalls

### Risk 1: Linux Desktop WebRTC and PipeWire Screen Capture (Critical)

**Status**: UNRESOLVED in current stack.

**Issue**: flutter_webrtc screenshare is broken on Wayland + PipeWire due to missing XDG Desktop Portal integration.
livekit_client has no Linux desktop support.

**Impact**: Linux desktop cannot perform screen sharing or media calls until fixed.

**Mitigation**:
1. Plan 4-6 weeks for FFI or wrapper implementation if targeting Linux 1.0.
2. Or, defer Linux desktop to 1.1 and prioritize iOS/Android for 1.0.
3. Monitor flutter_webrtc and livekit projects for community fixes (unlikely in near term).

**Timeline**: HIGH PRIORITY - Clarify early in development whether Linux desktop is in-scope for 1.0.

### Risk 2: Canvas Performance at Scale (High Object Count)

**Status**: UNVALIDATED.

**Issue**: CustomPainter with thousands of objects can exceed frame budget (8.3ms at 120fps, 16.7ms at 60fps), especially with complex paths and transparency.

**Impact**: Stuttering, dropped frames, poor UX, battery drain on mobile.

**Mitigation**:
1. Implement spatial culling (r_tree) before adding more than 100 drawable objects.
2. Profile early and often with Flutter DevTools "Performance" tab.
3. Set a hard cap on visible objects; mute off-screen drawing commands.
4. Benchmark on target devices (iPad, mid-range Android, Fedora workstation).

**Timeline**: Profile and validate during prototyping (week 2-3 of development).

### Risk 3: GIF and Image Memory on Mobile

**Status**: UNVALIDATED.

**Issue**: Multiple GIFs and high-resolution images on the canvas can quickly exceed mobile memory budgets (512MB-1GB for Flutter app).

**Impact**: Crashes from OOM, poor battery life, performance degradation.

**Mitigation**:
1. Limit concurrent animated GIFs to 5-10 (test on target devices).
2. Mute off-screen GIFs; decode only visible frames.
3. Use aggressive image downsampling for thumbnails.
4. Profile memory usage with `flutter run --profile` and DevTools.

**Timeline**: Benchmark during feature development; set memory limits early.

### Risk 4: Collaborative Editing Conflict Resolution

**Status**: DESIGN PENDING.

**Issue**: When two users draw on the same canvas simultaneously, the conflict-resolution strategy (deterministic tiebreaker, OT, CRDT) is not yet specified.

**Impact**: Undefined behavior; users may see different final states or data loss.

**Mitigation**: Design a formal conflict-resolution rule before implementing multi-user editing.
Use deterministic UUID comparison or server-assigned priority; document in the protocol specification (OpenAPI + JSON Schema).

**Timeline**: HIGH PRIORITY - Finalize conflict resolution design before 1.0 beta.

### Risk 5: LiveKit Dependency Coupling

**Status**: IDENTIFIED.

**Issue**: LiveKit's Flutter SDK is tightly coupled to the LiveKit infrastructure (server, SFU).
If LiveKit changes its API or licensing, migration is costly.

**Mitigation**: Abstract the media layer with a trait or interface (e.g., `MediaProvider` in Dart).
Keep LiveKit SDK calls isolated to one module.
Design for a potential swap to another SFU (e.g., Janus, Kurento) in the future.

**Timeline**: Structure code early to isolate LiveKit; do not scatter SDK calls across the app.

### Risk 6: Impeller Shader Compilation (iOS/Android)

**Status**: MITIGATED by Impeller design.

**Issue**: Impeller compiles shaders AOT; if an unhandled shader type is encountered at runtime, compilation may lag.

**Mitigation**: Use only Impeller-supported operations in CustomPainter.
Avoid heavy shader branching (if/else in fragment shaders); use math functions like mix(), smoothstep(), clamp().

**Timeline**: Part of code review; check CustomPainter shader usage in PR reviews.

### Risk 7: Riverpod Codegen Integration

**Status**: LOW RISK.

**Issue**: Riverpod's codegen (riverpod_generator) is powerful but adds a build step.
Misconfigured, it can cause build failures and slow cold builds.

**Mitigation**: Use the official Riverpod templates (flutter_riverpod starter) for correct build.yaml setup.
Run `dart run build_runner build` in CI to catch codegen issues early.

**Timeline**: Set up build runner in the initial project scaffold.

## Summary and Recommended Actions

### Confirmations (Use As-Is)

1. **Impeller + CustomPainter**: Right choice for canvas rendering; use RepaintBoundary and spatial culling.
2. **infinite_canvas**: Viable starting point; plan to extend for collaboration and scale.
3. **flutter_box_transform**: Ideal for draggable/resizable windows on the canvas.
4. **r_tree**: Use for spatial indexing (add as explicit dependency).
5. **Riverpod**: Best state management; confirmed for 2026.
6. **Drift**: Best local storage; confirmed for 2026.
7. **Axum + Tokio**: Solid WebSocket server; confirmed for production.
8. **flutter_secure_storage**: Confirmed for session tokens and device keys.
9. **GoRouter**: Confirmed for navigation.
10. **Lucide Icons**: Confirmed for UI consistency.

### Additions (Add to Dependency List)

1. **r_tree**: Spatial indexing for canvas culling.
2. **cached_network_image (CE)**: Community edition for cross-platform image caching.
3. **gif_player**: Optional but recommended for GIF control if canvas supports it.
4. **Dart FFI Binding to LiveKit C++**: Required for Linux desktop media support (significant development effort).
5. **XDG Desktop Portal Wrapper**: Required for Linux screen sharing (medium complexity).

### Changes (Swap or Adjust)

1. **Linux Desktop Media Architecture**: Replace livekit_client with LiveKit C++ SDK via FFI, or defer to post-1.0.
2. **Canvas Object Model**: Use hybrid CustomPainter + flutter_box_transform + spatial index, not monolithic CustomPainter.
3. **Conflict Resolution**: Design deterministic tiebreaker rule for simultaneous multi-user edits; finalize before 1.0.

### Critical Path Items (High Priority)

1. **Clarify Linux Desktop Scope**: Decide by end of week 1 whether Linux desktop is in-scope for 1.0; if yes, start FFI binding work immediately.
2. **Profile Canvas at Scale**: By week 2-3, build a reference implementation with 100-500 objects; measure frame rate and memory on target devices.
3. **Finalize Conflict Resolution**: Design and document tiebreaker rule for multi-user canvas editing before feature development begins.
4. **PipeWire/Wayland Integration Plan**: If Linux desktop is in-scope, allocate 4-6 weeks to XDG Desktop Portal wrapper or defer screen sharing to 1.1.

### 2026 Library Maintenance Status

All recommended libraries show active maintenance as of July 2026:
- livekit_client: Updated monthly, stable 2.8.1.
- flutter_webrtc: Issues and commits through early July 2026.
- Riverpod: Version 3.0+ with regular updates.
- Drift: Actively maintained on pub.dev.
- r_tree: Updated February 2026.
- Impeller: Default renderer in Flutter 4.0+ (core framework).
- Axum: Actively maintained by Tokio team; production deployments widespread.

No libraries in this stack are in maintenance mode or at risk of abandonment.

---

## References

### Official Documentation and Repositories

- [LiveKit Flutter SDK (pub.dev)](https://pub.dev/packages/livekit_client)
- [livekit/client-sdk-flutter (GitHub)](https://github.com/livekit/client-sdk-flutter)
- [flutter-webrtc/flutter-webrtc (GitHub)](https://github.com/flutter-webrtc/flutter-webrtc)
- [LiveKit C++ SDK (GitHub)](https://github.com/livekit/client-sdk-cpp)
- [r_tree (pub.dev)](https://pub.dev/packages/r_tree)
- [flutter_box_transform (pub.dev)](https://pub.dev/packages/flutter_box_transform)
- [infinite_canvas (pub.dev)](https://pub.dev/packages/infinite_canvas)
- [Riverpod (pub.dev)](https://pub.dev/packages/riverpod)
- [Drift (pub.dev)](https://pub.dev/packages/drift)
- [flutter_secure_storage (pub.dev)](https://pub.dev/packages/flutter_secure_storage)
- [cached_network_image (pub.dev)](https://pub.dev/packages/cached_network_image)
- [gif_player (pub.dev)](https://pub.dev/packages/gif_player)
- [Axum Web Framework (GitHub)](https://github.com/tokio-rs/axum)
- [Impeller Rendering Engine (Flutter Docs)](https://docs.flutter.dev/perf/impeller)
- [Flutter Gestures Library (Dart API)](https://api.flutter.dev/flutter/gestures/gestures-library.html)

### 2026 Technical Articles and Benchmarks

- [Flutter + Impeller: How to Achieve Native 120fps Performance in 2026](https://shindekalpesharun.medium.com/flutter-impeller-how-to-achieve-native-120fps-performance-in-2026-68ec28cc71e5)
- [Flutter State Management in 2026: Riverpod vs Bloc vs Provider in Production](https://dev.to/lycore/flutter-state-management-in-2026-riverpod-vs-bloc-vs-provider-in-production-2i53)
- [Building Real-Time Apps with Rust WebSockets: Tokio + Axum in 2026](https://rustify.rs/articles/rust-websocket-realtime-apps-tokio-axum-2026)
- [Rust Web Frameworks in 2026: Axum vs Actix Web vs Rocket vs Warp vs Salvo](https://aarambhdevhub.medium.com/rust-web-frameworks-in-2026-axum-vs-actix-web-vs-rocket-vs-warp-vs-salvo-which-one-should-you-2db3792c79a2)
- [Flutter Local Databases in Depth: drift, Isar & SQLite - Migrations, Relationships & Reactive Queries](https://medium.com/@alaxhenry0121/flutter-local-databases-in-depth-drift-isar-sqlite-migrations-relationships-reactive-90165af86b85)

### Linux and PipeWire Integration

- [Screenshare sources dialog crashes on Linux with pipewire (flutter-webrtc issue #1542)](https://github.com/flutter-webrtc/flutter-webrtc/issues/1542)
- [OBS Wayland Guide - Linux Screen Capture & PipeWire Setup](https://obs-versions.com/blog/obs-wayland-linux-guide/)
- [Wayland Screen Sharing: XDG Portal, PipeWire Fix](https://botmonster.com/self-hosting/wayland-screen-sharing-fix-video-calls-linux/)

---

**Document Date**: July 23, 2026.

**Reviewed By**: Media and Voice Canvas Rendering Engineer.

**Status**: Ready for development team review.
