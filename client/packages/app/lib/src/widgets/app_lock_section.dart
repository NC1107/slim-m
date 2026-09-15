// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The app-lock toggle, under Account & profile: whether opening slim-m
/// needs Face ID, a fingerprint, or the device passcode first.
///
/// Absent entirely off `supportsBiometricLock` (Linux desktop and the web,
/// where nothing answers a `local_auth` call) rather than shown and
/// disabled: a control that can never do anything is worse than no control.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_platform/platform.dart' show supportsBiometricLock;

import '../providers/app_lock_preference.dart';
import 'settings_section_header.dart';
import 'settings_toggle_row.dart';

class AppLockSection extends ConsumerWidget {
  const AppLockSection({super.key, this.supported});

  /// Injectable for tests, which otherwise run on whatever host the suite
  /// itself is on (Linux in CI); the real build reads `supportsBiometricLock`.
  final bool? supported;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(supported ?? supportsBiometricLock)) return const SizedBox.shrink();

    final enabled = ref.watch(appLockPreferenceProvider);
    return SettingsSectionCard(
      title: 'App lock',
      description:
          "Not a second login - the server never sees your face or your "
          "fingerprint, so this only gates slim-m once you're already "
          "signed in. After a real sign-out you still need your password.",
      children: [
        SettingsToggleRow(
          label: 'Require Face ID or a fingerprint to open slim-m',
          description:
              'Stops someone holding your unlocked device from opening '
              'slim-m and reading your messages. Falls back to your device '
              'passcode if biometrics fail or are not set up.',
          value: enabled,
          semanticLabel: 'Require Face ID or a fingerprint to open slim-m',
          onChanged: (next) =>
              ref.read(appLockPreferenceProvider.notifier).set(next),
        ),
      ],
    );
  }
}
