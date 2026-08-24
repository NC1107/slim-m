// SPDX-License-Identifier: Apache-2.0
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
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

Widget reducedMotionApp({
  required ProviderContainer container,
  required Widget child,
  Brightness brightness = Brightness.light,
}) => UncontrolledProviderScope(
  container: container,
  child: MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: MaterialApp(
      theme: buildTheme(
        brightness,
        brightness == Brightness.light ? AppTokens.light : AppTokens.dark,
      ),
      home: Scaffold(body: child),
    ),
  ),
);
