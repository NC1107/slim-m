// SPDX-License-Identifier: Apache-2.0
/// The two headers settings is built from: a group header naming who a run of
/// sections belongs to, and the section header each one opens with.
///
/// Pulled out of `settings_screen.dart` so a new section (the avatar one)
/// can share it without that file growing past its line budget.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// Names who the sections under it belong to: "Personal" is about the account
/// holder, "Space" is about the deployment everyone here shares.
///
/// A step up the type scale from [SettingsSectionHeader] rather than a
/// different colour, so the two levels stay apart for a reader who cannot
/// tell the colours apart.
class SettingsGroupHeader extends StatelessWidget {
  const SettingsGroupHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s24,
        AppSpacing.s16,
        0,
      ),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: AppText.heading.copyWith(
            color: tokens.textPrimary,
            fontWeight: AppWeights.semi,
            letterSpacing: AppText.heading.fontSize! * AppTracking.title,
          ),
        ),
      ),
    );
  }
}

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
          Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
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
