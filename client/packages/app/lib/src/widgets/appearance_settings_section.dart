// SPDX-License-Identifier: Apache-2.0
/// The appearance picker: follow the system, light, dark, or true black.
///
/// Its own file rather than another section inside `settings_screen.dart`,
/// which is already past the project's line budget, and for the same reason
/// the avatar section has one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import 'settings_section_header.dart';

/// The cards variant rather than the inline one: inline lays its options out
/// at intrinsic width with nothing to divide the row, so four labels overflow
/// a phone. Cards stretch to a common height instead, which needs a bounded
/// one, and a list gives its children none - hence the [IntrinsicHeight].
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
          description: 'Following the system picks light or dark, never true '
              'black: that one is a choice for an OLED screen.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            0,
            AppSpacing.s16,
            AppSpacing.s16,
          ),
          child: IntrinsicHeight(
            child: AppSegmentedControl.cards(
              semanticLabel: 'Appearance',
              options: [
                for (final option in AppThemeChoice.values)
                  AppSegmentedOption(label: _labelFor(option)),
              ],
              selectedIndex: AppThemeChoice.values.indexOf(choice),
              onSegmentSelected: (index) => ref
                  .read(themeControllerProvider.notifier)
                  .select(AppThemeChoice.values[index]),
            ),
          ),
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
