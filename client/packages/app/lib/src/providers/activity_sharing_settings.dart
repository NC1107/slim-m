// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Whether this device tells others what it is playing.
///
/// Off until the person turns it on (decision 0044), and one switch per
/// source so a later game source never rides on this one. A device-local
/// preference: the server never learns the setting, only the activity that an
/// enabled source produces.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

const shareListeningKey = 'slimm.presence.share_listening';

class ShareListeningController extends StateNotifier<bool> {
  ShareListeningController(this._ref) : super(false) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final prefs = await _ref.read(preferencesProvider.future);
    if (mounted) state = prefs.getBool(shareListeningKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await _ref.read(preferencesProvider.future);
    await prefs.setBool(shareListeningKey, enabled);
  }
}

final shareListeningProvider =
    StateNotifierProvider<ShareListeningController, bool>(
      (ref) => ShareListeningController(ref),
    );
