// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The switch for showing what you are listening to (decision 0044).
///
/// Off by default, and absent on a platform with no source rather than shown
/// dead. It sits in the Profile pane because it decides what your profile
/// card and member row say about you.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/activity_publisher.dart';
import '../providers/activity_sharing_settings.dart';
import 'settings_section_header.dart';
import 'settings_toggle_row.dart';

class ActivitySharingSection extends ConsumerWidget {
  const ActivitySharingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(nowPlayingSourceProvider) == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          'Activity',
          description:
              'Shown only to people who can already see your status, and '
              'never while you appear offline.',
        ),
        SettingsSectionCard(
          children: [
            SettingsToggleRow(
              label: 'Show what I am listening to',
              description:
                  'Reads the track from any player on this computer and '
                  'shows it on your profile card and member row. It clears '
                  'when you pause, stop or quit.',
              value: ref.watch(shareListeningProvider),
              onChanged: (value) =>
                  ref.read(shareListeningProvider.notifier).setEnabled(value),
              semanticLabel: 'Show what I am listening to',
            ),
          ],
        ),
      ],
    );
  }
}
