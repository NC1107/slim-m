// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Which channel categories this device has folded in the rail (design
/// review note 8/2). Per device, the same shape `auto_update_preference.dart`
/// already gives a single stored answer - a category id is globally unique,
/// so one flat set covers every Space this install ever opens.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart';

const collapsedCategoriesKey = 'slimm.rail.collapsed_categories';

/// Read directly (not through the provider), the same seam
/// [loadAutoUpdatePreference] gives a caller that already holds the prefs.
Set<String> loadCollapsedCategories(SharedPreferences prefs) =>
    prefs.getStringList(collapsedCategoriesKey)?.toSet() ?? const {};

class CollapsedCategoriesController extends StateNotifier<Set<String>> {
  CollapsedCategoriesController(this._ref) : super(const {}) {
    _load();
  }

  final Ref _ref;

  /// Set the instant a toggle runs, so a load still in flight from the
  /// constructor never overwrites it once it finally resolves - the same
  /// "the newer truth wins" race [AutoUpdateController] already guards.
  bool _toggled = false;

  Future<void> _load() async {
    final prefs = await _ref.read(preferencesProvider.future);
    if (!_toggled) state = loadCollapsedCategories(prefs);
  }

  Future<void> toggle(String categoryId) async {
    _toggled = true;
    final next = {...state};
    if (!next.remove(categoryId)) next.add(categoryId);
    state = next;
    final prefs = await _ref.read(preferencesProvider.future);
    await prefs.setStringList(collapsedCategoriesKey, next.toList());
  }
}

final collapsedCategoriesProvider =
    StateNotifierProvider<CollapsedCategoriesController, Set<String>>(
      CollapsedCategoriesController.new,
    );
