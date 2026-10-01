// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The one empty state for a settings or admin list: a sentence in a card.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import 'settings_section_header.dart';

/// The sentence alone, for a card that already exists around it.
class SettingsEmptyLine extends StatelessWidget {
  const SettingsEmptyLine(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s8),
      child: Text(
        message,
        style: AppText.body.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}

/// A pane with nothing to list: [message] in a card, top-left like every other group.
class SettingsEmpty extends StatelessWidget {
  const SettingsEmpty(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) =>
      SettingsSectionCard(children: [SettingsEmptyLine(message)]);
}
