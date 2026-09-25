// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The app's lifecycle state as one provider, so a widget that animates for
/// its own sake can stop when nobody is looking without registering its own
/// observer. `resumed` is the only state in which the window is focused and
/// visible: desktop embedders report `inactive` for an unfocused window and
/// `hidden` for a minimised one, and a phone's `inactive`/`paused` cover the
/// same ground.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppLifecycleNotifier extends StateNotifier<AppLifecycleState>
    with WidgetsBindingObserver {
  AppLifecycleNotifier()
    : super(
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
      ) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      this.state = state;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final appLifecycleProvider =
    StateNotifierProvider<AppLifecycleNotifier, AppLifecycleState>(
      (ref) => AppLifecycleNotifier(),
    );

/// Whether the window is focused and visible right now.
final appFocusedProvider = Provider<bool>(
  (ref) => ref.watch(appLifecycleProvider) == AppLifecycleState.resumed,
);
