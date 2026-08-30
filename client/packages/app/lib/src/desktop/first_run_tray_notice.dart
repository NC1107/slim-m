// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A first-time notice that closing hid or minimised the window rather than
/// quitting - decision 0012's answer to Alt+F4 and the X button being
/// indistinguishable: tell the person once, the first time it happens.
///
/// Shown on the window's next reopen rather than at the moment of closing:
/// the window is what is disappearing at that instant, so there is nothing
/// left to show a banner in until it is back.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/providers.dart';
import 'close_behavior.dart';

/// Keyed per [CloseAction] rather than one shared flag. The two outcomes
/// describe different realities - one names a tray icon that exists, the
/// other has none to name - and a person who has only ever seen one of
/// them has not been told about the other. If a machine's tray host later
/// appears or disappears (an extension toggled, a panel restarted), the
/// resolved path they actually hit changes too, and the notice for that
/// path has never been shown to them yet.
String firstRunTrayNoticeShownKey(CloseAction action) =>
    'slimm.desktop.tray_notice_shown.${action.name}';

class FirstRunTrayNotice {
  const FirstRunTrayNotice(this._prefs);

  final SharedPreferences _prefs;

  bool hasBeenShown(CloseAction action) =>
      _prefs.getBool(firstRunTrayNoticeShownKey(action)) ?? false;

  Future<void> markShown(CloseAction action) =>
      _prefs.setBool(firstRunTrayNoticeShownKey(action), true);
}

/// Which resolved [CloseAction] the notice is currently describing, or null
/// while hidden. Carrying the real outcome rather than a bare visibility
/// bool is what lets the banner say the true thing that just happened
/// instead of a guess it would have to re-probe to answer.
final firstRunTrayNoticeCloseActionProvider = StateProvider<CloseAction?>(
  (ref) => null,
);

/// The store, resolved from the same [preferencesProvider] every other
/// preference controller in this app reads from - one shared instance
/// rather than a second call to the platform channel behind it.
final firstRunTrayNoticeProvider = FutureProvider<FirstRunTrayNotice>(
  (ref) async =>
      FirstRunTrayNotice(await ref.watch(preferencesProvider.future)),
);
