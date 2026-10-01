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

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

const pushIncludeContentKey = 'slimm.notifications.push_include_content';

class PushContentPreviewController extends StateNotifier<bool> {
  PushContentPreviewController(this._ref) : super(false) {
    unawaited(_ensureLoaded());
  }

  final Ref _ref;
  Future<void>? _loading;
  bool _loaded = false;

  /// Awaited by [currentValue] and [setEnabled] so neither ever reads or
  /// writes the in-memory default ahead of the real, persisted value - a
  /// registration racing app startup must not silently send `false` for a
  /// device that actually has this turned on.
  ///
  /// Never throws: [currentValue] is on every registration's path. A failed
  /// read is retried by the next caller rather than remembered, because
  /// pinning the default for the whole process would keep sending `false`
  /// (and showing the row off) for a member who turned this on.
  Future<void> _ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    try {
      final prefs = await _ref.read(preferencesProvider.future);
      state = prefs.getBool(pushIncludeContentKey) ?? false;
      _loaded = true;
    } catch (_) {
      _ref.invalidate(preferencesProvider);
    }
  }

  /// The persisted value, for a caller (registration) that needs the real
  /// answer rather than whatever [state] happens to hold before a load
  /// succeeds.
  Future<bool> currentValue() async {
    await _ensureLoaded();
    return state;
  }

  Future<void> setEnabled(bool enabled) async {
    await _ensureLoaded();
    state = enabled;
    _loaded = true;
    final prefs = await _ref.read(preferencesProvider.future);
    await prefs.setBool(pushIncludeContentKey, enabled);
  }
}

final pushContentPreviewSettingsProvider =
    StateNotifierProvider<PushContentPreviewController, bool>(
      (ref) => PushContentPreviewController(ref),
    );
