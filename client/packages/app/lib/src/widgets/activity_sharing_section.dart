// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Every rich-presence switch, and what is being shared right now, in one
/// place (decision 0044).
///
/// Each source is off by default and absent on a platform that has none
/// rather than shown dead. It sits in the Profile pane because it decides
/// what your profile card and member row say about you.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/activity_feeds.dart';
import '../providers/activity_sharing_settings.dart';
import '../providers/presence_activity.dart';
import '../spotify/spotify_link.dart';
import 'activity_game_list.dart';
import 'settings_section_header.dart';
import 'settings_toggle_row.dart';

class ActivitySharingSection extends ConsumerWidget {
  const ActivitySharingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feeds = ref.watch(availableActivityFeedsProvider);
    if (feeds.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          'Activity',
          description:
              'Shown to people who see your status, never when appearing offline.',
        ),
        SettingsSectionCard(
          children: [
            for (final feed in feeds) ...[
              SettingsToggleRow(
                label: feed.label,
                description: feed.description,
                value: ref.watch(feed.enabled),
                onChanged: (value) =>
                    ref.read(feed.enabled.notifier).setEnabled(value),
                semanticLabel: feed.label,
              ),
              if (feed.enabled == shareGameProvider) const ActivityGameList(),
            ],
            const _LinkError(),
            const _SharingNow(),
          ],
        ),
      ],
    );
  }
}

class _LinkError extends ConsumerWidget {
  const _LinkError();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(spotifyLinkErrorProvider);
    if (message == null) return const SizedBox.shrink();
    return AppErrorState(
      message: message,
      onDismiss: () => ref.read(spotifyLinkErrorProvider.notifier).state = null,
    );
  }
}

class _SharingNow extends ConsumerWidget {
  const _SharingNow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shared = ref.watch(sharedActivityProvider);
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s8,
      ),
      child: Text(
        shared == null
            ? 'Sharing right now: nothing'
            : 'Sharing right now: ${describeActivity(shared)}',
        style: AppText.caption.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}
