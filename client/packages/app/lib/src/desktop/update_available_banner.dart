// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The visible half of `update_watch.dart`: a persistent, dismissible strip
/// saying a newer build is there, for someone who never quits long enough to
/// see the splash's own offer. Mounted in `DesktopChrome` beside
/// [FirstRunTrayNoticeBanner], the same "say it once, quietly, and let the
/// user dismiss it" shape that banner already uses instead of a `SnackBar`.
///
/// Deliberately says only that a restart gets it, not how: `startup_updates`
/// already knows the install-format-specific mechanism (dnf, the release
/// page, ...) and re-derives it the moment the app restarts, so repeating
/// that branching here would only be a second place for it to drift out of
/// sync with the splash's own copy.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import 'update_check.dart';
import 'update_watch.dart';

class UpdateAvailableBanner extends ConsumerWidget {
  const UpdateAvailableBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Forces UpdateWatcher into existence for as long as this stays mounted.
    ref.watch(updateWatcherProvider);
    final update = ref.watch(inSessionUpdateProvider);
    if (update == null) return const SizedBox.shrink();

    return AppCallout(
      tone: AppCalloutTone.info,
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Version ${update.version} is available. Restart slim-m to '
              'update.',
            ),
          ),
          AppIconButton(
            icon: AppIcons.dismiss,
            semanticLabel: 'Dismiss',
            size: AppIconButtonSize.sm,
            onPressed: () => _dismiss(ref, update),
          ),
        ],
      ),
    );
  }

  Future<void> _dismiss(WidgetRef ref, ClientUpdate update) async {
    ref.read(inSessionUpdateProvider.notifier).state = null;
    final prefs = await ref.read(preferencesProvider.future);
    await prefs.setString(dismissedUpdateVersionKey, update.version);
  }
}
