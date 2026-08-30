// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Whether the desktop startup splash shows at all, and how long it holds the
/// screen when it does, as a user setting.
///
/// Both controllers restore and persist on every platform, the same as every
/// other performance preference - only `main.dart`'s bootstrap sequence,
/// itself a no-op off Linux/macOS/Windows, ever reads them to pick
/// [awaitBootstrapWithSplashFloor]'s own floor. [PerformanceSettingsSection]
/// hides both rows outside a desktop host, since neither does anything on a
/// phone or the web.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../desktop/splash_floor.dart' show minSplashDuration;
import 'providers.dart';

const desktopSplashEnabledKey = 'slimm.performance.desktop_splash_enabled';

/// On by default: this is the behaviour every existing install already has,
/// so leaving the setting alone changes nothing.
const defaultDesktopSplashEnabled = true;

class SplashEnabledController extends StateNotifier<bool> {
  SplashEnabledController(this._ref) : super(defaultDesktopSplashEnabled);

  final Ref _ref;

  /// A missing stored value leaves the default alone, the same degrade every
  /// other performance preference in this app uses.
  Future<void> restore() async {
    try {
      final prefs = await _ref.read(preferencesProvider.future);
      state =
          prefs.getBool(desktopSplashEnabledKey) ?? defaultDesktopSplashEnabled;
    } catch (_) {
      // On is always a usable answer.
    }
  }

  Future<void> select(bool enabled) async {
    state = enabled;
    final prefs = await _ref.read(preferencesProvider.future);
    await prefs.setBool(desktopSplashEnabledKey, enabled);
  }
}

final splashEnabledControllerProvider =
    StateNotifierProvider<SplashEnabledController, bool>(
      SplashEnabledController.new,
    );

/// A small set of named floors rather than a millisecond slider: nobody
/// thinks in milliseconds, and [minSplashDuration]'s own history (280ms, then
/// 560ms, then 900ms, each retuned against a real run) is exactly the kind of
/// value a slider invites a user to mistune with none of the owner's own
/// eyes-on feedback loop to catch it.
enum SplashDuration { brief, standard, long }

extension SplashDurationX on SplashDuration {
  /// The floor [awaitBootstrapWithSplashFloor] waits out when the splash is
  /// enabled. [standard] is [minSplashDuration] itself, not a second copy of
  /// 900ms, so the two can never drift apart.
  Duration get duration => switch (this) {
    SplashDuration.brief => const Duration(milliseconds: 500),
    SplashDuration.standard => minSplashDuration,
    SplashDuration.long => const Duration(milliseconds: 1500),
  };

  String get label => switch (this) {
    SplashDuration.brief => 'Brief',
    SplashDuration.standard => 'Standard (default)',
    SplashDuration.long => 'Long',
  };
}

const desktopSplashDurationKey = 'slimm.performance.desktop_splash_duration';

const defaultSplashDuration = SplashDuration.standard;

class SplashDurationController extends StateNotifier<SplashDuration> {
  SplashDurationController(this._ref) : super(defaultSplashDuration);

  final Ref _ref;

  /// A missing or unrecognised stored value leaves the default alone, the
  /// same degrade the other named-choice preferences use.
  Future<void> restore() async {
    try {
      final prefs = await _ref.read(preferencesProvider.future);
      final stored = prefs.getString(desktopSplashDurationKey);
      for (final value in SplashDuration.values) {
        if (value.name == stored) {
          state = value;
          return;
        }
      }
    } catch (_) {
      // Not worth failing a launch over; standard is always usable.
    }
  }

  Future<void> select(SplashDuration value) async {
    state = value;
    final prefs = await _ref.read(preferencesProvider.future);
    await prefs.setString(desktopSplashDurationKey, value.name);
  }
}

final splashDurationControllerProvider =
    StateNotifierProvider<SplashDurationController, SplashDuration>(
      SplashDurationController.new,
    );

/// The one place "on or off, and which duration" turns into the single
/// [Duration] [awaitBootstrapWithSplashFloor] needs. Pulled out as its own
/// pure function, rather than left inline in `main.dart`'s private bootstrap
/// helper, specifically so it is unit-testable: `main.dart`'s own bootstrap
/// path is never exercised in tests (decision 0012's "never raise a real
/// window" rule), so this is the one place the on/off decision itself can be
/// mutation-tested at all.
Duration splashFloorFor({
  required bool enabled,
  required SplashDuration duration,
}) => enabled ? duration.duration : Duration.zero;
