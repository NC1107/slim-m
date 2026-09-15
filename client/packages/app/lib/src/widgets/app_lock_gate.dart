// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The biometric app lock's own layer in `appChromeBuilder`'s stack: renders
/// `AppLockScreen` over everything else while
/// `appLockControllerProvider` reports locked, and nothing otherwise.
///
/// An overlay rather than a swap of the routed app for the lock screen (the
/// shape `ClientTooOldGate` uses for its own, unrecoverable state): the
/// routed `Navigator` underneath stays mounted the whole time slim-m is
/// locked, so a resume-triggered lock never loses scroll position, an
/// in-progress compose draft, or any other state a rebuilt tree would drop.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_lock_controller.dart';
import 'app_lock_screen.dart';

class AppLockGate extends ConsumerWidget {
  const AppLockGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(appLockControllerProvider);
    return locked ? const AppLockScreen() : const SizedBox.shrink();
  }
}
