// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The layer that shows a refused moderation write, wherever it was started.
///
/// Mounted once by `appChromeBuilder`, like `ToastOverlay`, because the write
/// is started from surfaces that close before it answers (a row menu, the
/// profile popover, the call screen) and the member pane that used to hold the
/// failure is a closed drawer on a phone. A persistent error state, not a
/// toast: it stays until dismissed or the next write starts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/member_moderation_error.dart';

class ModerationErrorHost extends ConsumerWidget {
  const ModerationErrorHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(memberModerationErrorProvider);
    if (message == null) return const SizedBox.shrink();

    final compact = MediaQuery.sizeOf(context).width < kCompactWidth;
    return SafeArea(
      child: Align(
        alignment: compact ? Alignment.topCenter : Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Material(
              type: MaterialType.transparency,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).extension<AppTokens>()!.surfaceBase,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: AppErrorState(
                  key: const Key('moderation-error'),
                  message: message,
                  onDismiss: () =>
                      ref.read(memberModerationErrorProvider.notifier).state =
                          null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
