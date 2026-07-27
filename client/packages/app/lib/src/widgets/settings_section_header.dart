// SPDX-License-Identifier: Apache-2.0
/// The title-plus-description header every settings section opens with.
/// Pulled out of `settings_screen.dart` so a new section (the avatar one)
/// can share it without that file growing past its line budget.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.title, {super.key, this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s24,
        AppSpacing.s16,
        AppSpacing.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              description!,
              style: TextStyle(color: tokens.textSecondary, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
