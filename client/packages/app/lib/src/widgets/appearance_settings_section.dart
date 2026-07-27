// SPDX-License-Identifier: Apache-2.0
/// The appearance picker: follow the system, light, dark, or true black.
///
/// Its own file rather than another section inside `settings_screen.dart`,
/// which is already past the project's line budget, and for the same reason
/// the avatar section has one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'settings_section_header.dart';
import 'settings_select_row.dart';

/// A select row rather than segmented cards. Four cards on a phone wrap their
/// labels mid-word, which is how "Online" rendered as "Onlin e" in the
/// presence picker next door, and they cost four rows of height to say one
/// thing.
class AppearanceSettingsSection extends ConsumerWidget {
  const AppearanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(themeControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          'Appearance',
          description: 'System never picks true black.',
        ),
        SettingsSelectRow<AppThemeChoice>(
          label: 'Theme',
          value: choice,
          choices: [
            for (final option in AppThemeChoice.values)
              SettingsChoice(value: option, label: _labelFor(option)),
          ],
          onChanged: (next) =>
              ref.read(themeControllerProvider.notifier).select(next),
        ),
      ],
    );
  }

  String _labelFor(AppThemeChoice choice) => switch (choice) {
    AppThemeChoice.system => 'System',
    AppThemeChoice.light => 'Light',
    AppThemeChoice.dark => 'Dark',
    AppThemeChoice.trueBlack => 'True black',
  };
}
