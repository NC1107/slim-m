// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Whether push envelopes carry a message preview, as the member sees and
/// changes it.
///
/// The truth is the account's choice on the server (`GET /push/preview`), so a
/// reinstall or a new device shows the same answer without anyone toggling
/// anything. The local `SharedPreferences` key holds only an explicit choice
/// the server has not yet accepted; registration sends `include_content` only
/// while one is pending, so a device that never toggled can never overwrite a
/// choice made on another.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart';

import 'providers.dart';

const pushIncludeContentKey = 'slimm.notifications.push_include_content';

/// State is the effective value, or null while the server has not answered.
class PushContentPreviewController extends StateNotifier<bool?> {
  PushContentPreviewController(this._ref) : super(null) {
    unawaited(refresh());
  }

  final Ref _ref;
  bool _chosen = false;

  /// Reads the account's effective value; a failure leaves it unknown rather
  /// than guessing, and a pending explicit choice is shown meanwhile.
  Future<void> refresh() async {
    final pending = await pendingChoice();
    if (pending != null && !_chosen) state = pending;
    try {
      final served = await _ref.read(apiProvider).pushPreview();
      if (!_chosen) state = served;
    } catch (_) {
      // state keeps the pending choice, or stays unknown.
    }
  }

  /// The explicit choice the server has not confirmed yet, or null. Never
  /// throws: it is on every registration's path, and a failed read is retried
  /// by the next caller because the cached provider error is invalidated.
  Future<bool?> pendingChoice() async {
    try {
      final prefs = await _ref.read(preferencesProvider.future);
      return prefs.getBool(pushIncludeContentKey);
    } catch (_) {
      _ref.invalidate(preferencesProvider);
      return null;
    }
  }

  /// Drops the pending choice once the server holds it.
  Future<void> markSent() async {
    try {
      final prefs = await _ref.read(preferencesProvider.future);
      await prefs.remove(pushIncludeContentKey);
    } catch (_) {
      _ref.invalidate(preferencesProvider);
    }
  }

  /// Saves the member's explicit choice to the account. If the server cannot
  /// be reached the choice is kept as pending and sent with the next
  /// registration.
  Future<void> setEnabled(bool enabled) async {
    _chosen = true;
    state = enabled;
    try {
      final prefs = await _ref.read(preferencesProvider.future);
      await prefs.setBool(pushIncludeContentKey, enabled);
    } catch (_) {
      _ref.invalidate(preferencesProvider);
    }
    try {
      await _ref.read(apiProvider).setPushPreview(enabled);
      await markSent();
    } catch (_) {
      // Left pending on purpose; see above.
    }
  }
}

final pushContentPreviewSettingsProvider =
    StateNotifierProvider<PushContentPreviewController, bool?>(
      (ref) => PushContentPreviewController(ref),
    );
