// SPDX-License-Identifier: Apache-2.0
/// Choosing which screen to share, on the desktops that make the app ask.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

/// Returns the chosen source, or null if the sheet was dismissed.
Future<ScreenShareSource?> showScreenSourceSheet(
  BuildContext context,
  List<ScreenShareSource> sources,
) {
  return showAppSheet<ScreenShareSource>(
    context,
    builder: (context) => _ScreenSourceSheet(sources: sources),
  );
}

class _ScreenSourceSheet extends StatelessWidget {
  const _ScreenSourceSheet({required this.sources});

  final List<ScreenShareSource> sources;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              0,
              AppSpacing.s16,
              AppSpacing.s4,
            ),
            child: Text('Share a screen', style: AppText.heading),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              0,
              AppSpacing.s16,
              AppSpacing.s12,
            ),
            child: Text(
              'Everyone in the call will see it until you stop sharing.',
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
          ),
          for (final source in sources)
            ListTile(
              leading: const Icon(AppIcons.screenShare),
              title: Text(source.name),
              onTap: () => Navigator.of(context).pop(source),
            ),
          const SizedBox(height: AppSpacing.s8),
        ],
      ),
    );
  }
}
