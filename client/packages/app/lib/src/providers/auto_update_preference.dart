// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Whether this install may update itself on launch.
///
/// Three states, not two: null means the question has never been answered,
/// and that is a real state the splash and the join flow both act on by
/// asking once. The owner's shape (decision 0025): asked during signup,
/// toggleable in Settings under About, and when on, the mini splash grabs
/// an update on every open before the app starts.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart';

const autoUpdateKey = 'slimm.updates.automatic';

/// The stored answer, or null when nobody has been asked. Read directly
/// (not through the provider) by the splash, which runs before the widget
/// tree exists.
bool? loadAutoUpdatePreference(SharedPreferences prefs) =>
    prefs.containsKey(autoUpdateKey) ? prefs.getBool(autoUpdateKey) : null;

class AutoUpdateController extends StateNotifier<bool?> {
  AutoUpdateController(this._ref) : super(null) {
    _load();
  }

  final Ref _ref;

  /// The stored answer, unless one was given while this was still reading:
  /// an answer made here and now is the newer truth, and letting the load
  /// land on top of it would silently undo the switch the user just moved.
  Future<void> _load() async {
    final prefs = await _ref.read(preferencesProvider.future);
    if (state == null) state = loadAutoUpdatePreference(prefs);
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    final prefs = await _ref.read(preferencesProvider.future);
    await prefs.setBool(autoUpdateKey, enabled);
  }
}

final autoUpdateProvider = StateNotifierProvider<AutoUpdateController, bool?>(
  AutoUpdateController.new,
);
