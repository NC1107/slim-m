// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Whether this device asks the server to seal a message preview inside its
/// push envelope, so a notification can show who sent it and part of what it
/// says rather than the relay's generic fallback string.
///
/// A pure local device preference with no server truth of its own, the same
/// shape `notification_sound_settings.dart` already documents - except this
/// one really is device-scoped rather than merely stored per device: the
/// server's own `include_content` field (`http/push.rs`) is read per
/// registration, so a personal phone and a shared tablet on the same account
/// can answer differently, matching where `SharedPreferences` already lives.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

const pushIncludeContentKey = 'slimm.notifications.push_include_content';

class PushContentPreviewController extends StateNotifier<bool> {
  PushContentPreviewController(this._ref) : super(false) {
    _ready = _load();
  }

  final Ref _ref;

  /// Awaited by [currentValue] and [setEnabled] so neither ever reads or
  /// writes the in-memory default ahead of the real, persisted value - a
  /// registration racing app startup must not silently send `false` for a
  /// device that actually has this turned on.
  ///
  /// Never throws: [currentValue] is on every registration's path, and a
  /// device whose local storage briefly fails still deserves a real
  /// registration rather than [PushController] reading it as a server error.
  late final Future<void> _ready;

  Future<void> _load() async {
    try {
      final prefs = await _ref.read(preferencesProvider.future);
      state = prefs.getBool(pushIncludeContentKey) ?? false;
    } catch (_) {
      // state already holds this class's own false default; see above.
    }
  }

  /// The persisted value, for a caller (registration) that needs the real
  /// answer rather than whatever [state] happens to hold before [_load]
  /// finishes.
  Future<bool> currentValue() async {
    await _ready;
    return state;
  }

  Future<void> setEnabled(bool enabled) async {
    await _ready;
    state = enabled;
    final prefs = await _ref.read(preferencesProvider.future);
    await prefs.setBool(pushIncludeContentKey, enabled);
  }
}

final pushContentPreviewSettingsProvider =
    StateNotifierProvider<PushContentPreviewController, bool>(
      (ref) => PushContentPreviewController(ref),
    );
