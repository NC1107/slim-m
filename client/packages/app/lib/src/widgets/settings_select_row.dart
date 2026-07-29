// SPDX-License-Identifier: Apache-2.0
/// A settings row that states its current value and opens a sheet to change it.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// One choice offered by a [SettingsSelectRow].
class SettingsChoice<T> {
  const SettingsChoice({required this.value, required this.label});

  final T value;
  final String label;
}

/// Replaces a row of segmented cards for settings with more than about three
/// options. Four cards on a phone wrap their labels mid-word, and the value a
/// setting currently holds is what a reader is looking for anyway.
class SettingsSelectRow<T> extends StatelessWidget {
  const SettingsSelectRow({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.sheetTitle,
  });

  final String label;
  final T value;
  final List<SettingsChoice<T>> choices;
  final ValueChanged<T> onChanged;

  /// Defaults to [label]; set it where the row's label is too terse to head a
  /// sheet on its own.
  final String? sheetTitle;

  String get _currentLabel => choices
      .firstWhere((c) => c.value == value, orElse: () => choices.first)
      .label;

  /// Opens the choice sheet standalone, for a caller that wants this row's
  /// picker without its [AppListRow] presentation: [JoinPolicyRow] renders
  /// as a [ListTile] to match its neighbours but still needs this sheet.
  static Future<T?> pick<T>(
    BuildContext context, {
    required String title,
    required T value,
    required List<SettingsChoice<T>> choices,
  }) {
    return showAppSheet<T>(
      context,
      bare: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: AppMenu(
          children: [
            AppMenuLabel(title),
            for (final choice in choices)
              AppMenuItem(
                label: choice.label,
                selected: choice.value == value,
                leading: choice.value == value ? AppIcons.check : null,
                onTap: () => Navigator.of(sheetContext).pop(choice.value),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final chosen = await pick<T>(
      context,
      title: sheetTitle ?? label,
      value: value,
      choices: choices,
    );
    if (chosen != null && chosen != value) onChanged(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return AppListRow(
      label: label,
      meta: _currentLabel,
      semanticLabel: '$label, currently $_currentLabel',
      trailing: Icon(
        AppIcons.chevronRight,
        size: 16,
        color: tokens.textSecondary,
      ),
      onTap: () => _open(context),
    );
  }
}
