// SPDX-License-Identifier: Apache-2.0
/// Persists [WindowGeometry] as one JSON blob under one key, the same
/// one-value-per-feature shape `display_preferences.dart`'s controllers
/// already use, rather than five separate keys for size, position and state.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'window_geometry.dart';

const windowGeometryPreferenceKey = 'slimm.desktop.window_geometry';

class WindowGeometryStore {
  const WindowGeometryStore(this._prefs);

  final SharedPreferences _prefs;

  /// Null on a fresh install, or if the stored value is corrupt - a broken
  /// blob degrades to "nothing saved yet" rather than a crash on launch.
  WindowGeometry? read() {
    final raw = _prefs.getString(windowGeometryPreferenceKey);
    if (raw == null) return null;
    try {
      return WindowGeometry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(WindowGeometry geometry) => _prefs.setString(
    windowGeometryPreferenceKey,
    jsonEncode(geometry.toJson()),
  );
}
