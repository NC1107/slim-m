// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The gap `update_check.dart`'s own doc names: that check only ever runs
/// during the splash, so someone who leaves slim-m open for days is never
/// told a newer build exists until they happen to quit and relaunch.
///
/// This re-runs the same best-effort, format-aware check on a repeating
/// timer for as long as the app stays open, and surfaces a find through
/// [inSessionUpdateProvider] rather than a prompt - [UpdateAvailableBanner]
/// (`update_available_banner.dart`) is the only thing that reads it.
///
/// Everything decision 0020/0025 already decided still applies: nothing is
/// downloaded or executed, a failure resolves to no update rather than an
/// error, and `SLIMM_NO_UPDATE_CHECK` (see [updateChecksDisabled]) still
/// switches this off entirely, the same as the splash.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_platform/platform.dart';

import '../providers/providers.dart';
import 'update_check.dart';

/// GitHub allows 60 unauthenticated requests per hour per source IP. Once
/// every six hours is four requests a day from this check - even an install
/// left running for months of uninterrupted uptime stays orders of magnitude
/// under a limit it would need to poll roughly 15x more often to ever risk.
const updateWatchInterval = Duration(hours: 6);

/// Whether this build should ever run the periodic check at all: a desktop
/// host that has not opted out with `SLIMM_NO_UPDATE_CHECK`, the same rule
/// `startup_updates.dart` applies to the splash's own one-shot check.
bool updateWatchShouldRun() => isDesktopHost && !updateChecksDisabled();

/// Runs [checkForClientUpdate] every [interval] for as long as something
/// keeps [updateWatcherProvider] alive, writing a find that has not already
/// been dismissed into [inSessionUpdateProvider].
///
/// No immediate first check on construction, unlike [VoiceCallHeartbeat]'s
/// proof-of-life ping: the splash this same session just passed through
/// already made one, and firing a second immediately after would only spend
/// part of the rate-limit budget above for no new information.
class UpdateWatcher {
  UpdateWatcher(
    this._ref, {
    this.interval = updateWatchInterval,
    CheckForClientUpdate check = checkForClientUpdate,
    InstallFormat? format,
    bool Function() shouldRun = updateWatchShouldRun,
  }) : _check = check,
       _format = format,
       _shouldRun = shouldRun;

  final Ref _ref;
  final Duration interval;
  final CheckForClientUpdate _check;
  final InstallFormat? _format;
  final bool Function() _shouldRun;
  Timer? _timer;

  /// Starts the timer, unless it is running already or [shouldRun] (a
  /// desktop host with the check not switched off) says this session should
  /// never poll at all.
  void start() {
    if (_timer != null || !_shouldRun()) return;
    _timer = Timer.periodic(interval, (_) => unawaited(_poll()));
  }

  void dispose() => _timer?.cancel();

  Future<void> _poll() async {
    try {
      final info = await _ref.read(appInfoProvider.future);
      final update = await _check(
        currentVersion: info.version,
        format: _format,
      );
      if (update == null) return;

      final prefs = await _ref.read(preferencesProvider.future);
      if (updateWasDismissed(
        dismissed: prefs.getString(dismissedUpdateVersionKey),
        candidate: update.version,
      )) {
        return;
      }
      _ref.read(inSessionUpdateProvider.notifier).state = update;
    } catch (_) {
      // Best-effort, same as the splash's own check: try again next tick.
    }
  }
}

/// The update this session's periodic check has found and not yet
/// dismissed, or null. Dismissing it (see `update_available_banner.dart`)
/// writes the same [dismissedUpdateVersionKey] the splash's own "Not now"
/// does, so either surface's dismissal holds for the other.
final inSessionUpdateProvider = StateProvider<ClientUpdate?>((ref) => null);

/// Forces [UpdateWatcher] into existence for as long as
/// [UpdateAvailableBanner] is mounted - see that widget, the one place that
/// watches this. Nothing here reads its own state; the timer it starts is
/// the entire point.
final updateWatcherProvider = Provider.autoDispose<UpdateWatcher>((ref) {
  final watcher = UpdateWatcher(ref);
  watcher.start();
  ref.onDispose(watcher.dispose);
  return watcher;
});
