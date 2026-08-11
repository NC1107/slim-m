// SPDX-License-Identifier: Apache-2.0
/// The first-time notice itself: shown once, the first time the window
/// reopens after closing minimised it rather than quitting. Persistent
/// rather than a timed `SnackBar` - this app's own established rule for
/// anything worth a person actually reading, not a toast that can vanish
/// before it is seen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import 'first_run_tray_notice.dart';

class FirstRunTrayNoticeBanner extends ConsumerWidget {
  const FirstRunTrayNoticeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(firstRunTrayNoticeVisibleProvider);
    if (!visible) return const SizedBox.shrink();

    return AppCallout(
      tone: AppCalloutTone.info,
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'slim-m is still running in the tray. Use the tray icon to '
              'reopen or quit it.',
            ),
          ),
          AppIconButton(
            icon: AppIcons.dismiss,
            semanticLabel: 'Dismiss',
            size: AppIconButtonSize.sm,
            onPressed: () => _dismiss(ref),
          ),
        ],
      ),
    );
  }

  Future<void> _dismiss(WidgetRef ref) async {
    ref.read(firstRunTrayNoticeVisibleProvider.notifier).state = false;
    final notice = await ref.read(firstRunTrayNoticeProvider.future);
    await notice.markShown();
  }
}
