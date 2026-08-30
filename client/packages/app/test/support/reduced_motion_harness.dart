// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The reduced-motion app harness for any widget that may mount an
/// `AppSpeakingRing`.
///
/// The ring starts a perpetual `repeat(reverse: true)` pulse the instant a
/// call is joined - a member profile, a voice tile, a presence bubble all pull
/// it in - and a real repeating ticker never lets `pumpAndSettle` settle, so a
/// test that mounts one hangs forever unless animations are off. Every such
/// test used to wrap its widget in this by hand; folding it into one place is
/// so the next test to mount a speaking-capable widget reaches for this rather
/// than rediscovering the hang (TEST14). Reach for it wherever a widget can
/// show a speaking ring; harmless anywhere else.
///
/// [reducedMotionApp] covers a widget reachable under a bare
/// `MaterialApp(home:)`. [reducedMotionRouterApp] is the sibling for a widget
/// only reachable by pushing through a real `GoRouter` - `context.go`,
/// `Navigator.of(context, rootNavigator: true).pop()`, a `ShellRoute`'s own
/// `Scaffold` - none of which exist under a plain `home:`. A single function
/// taking both a `child` and a `router` would have to make one of two
/// required parameters optional and assert against the other being set too,
/// which trades a compile-time contract for a runtime one; two named
/// functions keep each shape's own required parameter exactly that.
/// [reducedMotionData] is for a widget under test that carries no app shell
/// at all - no `MaterialApp`, no `ProviderContainer` - so wrapping it in
/// either of the above would change what is actually being exercised; it
/// hands back just the `MediaQueryData` every other builder here constructs
/// internally, for a caller to place directly under its own `MediaQuery`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';

/// A `MediaQueryData` with reduced motion applied, for a widget under test
/// with no `MaterialApp`/`ProviderContainer` shell to hang it off - the one
/// shape [reducedMotionApp] and [reducedMotionRouterApp] cannot cover.
MediaQueryData reducedMotionData({bool disableAnimations = true}) =>
    MediaQueryData(disableAnimations: disableAnimations);

Widget reducedMotionApp({
  required ProviderContainer container,
  required Widget child,
  Brightness brightness = Brightness.light,
  bool disableAnimations = true,
}) => UncontrolledProviderScope(
  container: container,
  child: MediaQuery(
    data: reducedMotionData(disableAnimations: disableAnimations),
    child: MaterialApp(
      theme: buildTheme(
        brightness,
        brightness == Brightness.light ? AppTokens.light : AppTokens.dark,
      ),
      home: Scaffold(body: child),
    ),
  ),
);

/// The router-aware sibling of [reducedMotionApp]. [size] becomes the whole
/// app's reported `MediaQueryData.size` outright, not a `copyWith` of
/// whatever the ambient test view already reports, so a caller can force the
/// compact-vs-desktop choice `showMemberProfile` and friends make from
/// `MediaQuery.sizeOf` rather than inherit whatever the default test window
/// happens to be; omit it to keep the zero-size default every caller here
/// relied on before this helper existed.
Widget reducedMotionRouterApp({
  required ProviderContainer container,
  required GoRouter router,
  Brightness brightness = Brightness.light,
  bool disableAnimations = true,
  Size? size,
}) => UncontrolledProviderScope(
  container: container,
  child: MediaQuery(
    data: MediaQueryData(
      size: size ?? Size.zero,
      disableAnimations: disableAnimations,
    ),
    child: MaterialApp.router(
      theme: buildTheme(
        brightness,
        brightness == Brightness.light ? AppTokens.light : AppTokens.dark,
      ),
      routerConfig: router,
    ),
  ),
);
