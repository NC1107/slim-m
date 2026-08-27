// SPDX-License-Identifier: Apache-2.0
/// A minimum visible duration for [StartupScreen], so a warm desktop start -
/// whose bootstrap often resolves in a frame or two - still reads as a real
/// splash rather than flashing invisibly, per the owner's own report that no
/// splash was perceptible on desktop at all.
///
/// Desktop only. [MobileBootGate] already covers the perceptible gap on a
/// phone - the first sync catch-up, not this pre-`runApp` bootstrap - with
/// its own splash; forcing this floor there too would only add latency to
/// every phone cold start for a screen [MobileBootGate] already makes
/// redundant.
///
/// Not gated on reduce-motion. [minSplashDuration] holds a static frame on
/// screen for longer, it does not animate one: [StartupScreen]'s own
/// [AppFadeIn] already collapses to an instant landing under reduce-motion,
/// which is the actual motion this app owes that setting. A floor with
/// nothing moving carries none of the vestibular concern reduce-motion
/// exists for.
library;

import 'dart:async';

import 'package:slimm_design_system/design_system.dart' show AppMotion;
import 'package:slimm_platform/platform.dart' show isDesktopHost;

/// How long [StartupScreen] must stay up on a desktop host before
/// [awaitBootstrapWithSplashFloor] lets readiness flip, even when bootstrap
/// itself finishes sooner.
///
/// Reuses [AppMotion.slow] rather than a new constant: it is already this
/// design language's own ceiling ("nothing in the chrome runs longer than
/// 280ms", `docs/design/design-language.md`), so the splash floor never asks
/// for more patience than the app already asks elsewhere - long enough on a
/// warm start to register as a deliberate screen, short enough that a cold
/// start already slower than it never feels padded on top.
const Duration minSplashDuration = AppMotion.slow;

/// Runs [bootstrap] to completion, and on [desktop] also waits out
/// [minSplashDuration] - whichever finishes later.
///
/// The two run concurrently, not back to back: the floor starts counting
/// before [bootstrap] is awaited, so a bootstrap slower than the floor is
/// never delayed by it, and only a bootstrap faster than the floor waits out
/// the remainder. [desktop] defaults to [isDesktopHost] (a getter, so it
/// cannot be a default parameter value directly) and exists as a parameter
/// purely so tests can drive both branches without a real host.
Future<void> awaitBootstrapWithSplashFloor(
  Future<void> Function() bootstrap, {
  bool? desktop,
}) async {
  final onDesktop = desktop ?? isDesktopHost;
  final floor = onDesktop ? Future<void>.delayed(minSplashDuration) : null;
  await bootstrap();
  if (floor != null) await floor;
}
