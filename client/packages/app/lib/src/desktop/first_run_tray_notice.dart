// SPDX-License-Identifier: Apache-2.0
/// A first-time-only notice that closing minimised to the tray rather than
/// quitting - the answer decision 0012 leaves to the owner: Alt+F4 and the X
/// button cannot be told apart, so the compensation Discord and Slack both
/// use is telling the person once, the first time it happens.
///
/// Shown on the window's next reopen rather than at the moment of closing:
/// the window is what is disappearing at that instant, so there is nothing
/// left to show a banner in until it is back.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/providers.dart';

const firstRunTrayNoticeShownKey = 'slimm.desktop.tray_notice_shown';

class FirstRunTrayNotice {
  const FirstRunTrayNotice(this._prefs);

  final SharedPreferences _prefs;

  bool get hasBeenShown => _prefs.getBool(firstRunTrayNoticeShownKey) ?? false;

  Future<void> markShown() => _prefs.setBool(firstRunTrayNoticeShownKey, true);
}

/// Whether the notice should render right now. A plain [StateProvider]
/// rather than tied to [FirstRunTrayNotice] itself, since the store's own
/// answer only matters once, at the moment a reopen decides whether to flip
/// this - after that the banner's own visibility is ordinary widget state.
final firstRunTrayNoticeVisibleProvider = StateProvider<bool>((ref) => false);

/// The store, resolved from the same [preferencesProvider] every other
/// preference controller in this app reads from - one shared instance
/// rather than a second call to the platform channel behind it.
final firstRunTrayNoticeProvider = FutureProvider<FirstRunTrayNotice>(
  (ref) async =>
      FirstRunTrayNotice(await ref.watch(preferencesProvider.future)),
);
