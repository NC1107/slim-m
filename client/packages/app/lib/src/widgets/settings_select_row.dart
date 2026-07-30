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
    this.sheetFootnote,
    this.unknownLabel = 'Unknown',
  });

  final String label;

  /// Null means "no choice known yet", not any of [choices]: a caller with
  /// nothing to read the current value back from must be able to say so
  /// rather than being forced to assert one of the real choices in its place.
  final T? value;
  final List<SettingsChoice<T>> choices;
  final ValueChanged<T> onChanged;

  /// Defaults to [label]; set it where the row's label is too terse to head a
  /// sheet on its own.
  final String? sheetTitle;

  /// A caveat line under the choices, shown where the reader is actually
  /// weighing them rather than as a section caption answering a question
  /// nobody asked yet.
  final String? sheetFootnote;

  /// Shown in place of a choice's label when [value] is null. Must never be a
  /// real choice's own label, or "not known" reads as that choice.
  final String unknownLabel;

  String get _currentLabel {
    final current = value;
    if (current == null) return unknownLabel;
    return choices
        .firstWhere((c) => c.value == current, orElse: () => choices.first)
        .label;
  }

  /// Opens the choice sheet standalone, for a caller that wants this row's
  /// picker without its [AppListRow] presentation: [JoinPolicyRow] renders
  /// as a [ListTile] to match its neighbours but still needs this sheet.
  static Future<T?> pick<T>(
    BuildContext context, {
    required String title,
    required T? value,
    required List<SettingsChoice<T>> choices,
    String? footnote,
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
            if (footnote != null) AppMenuLabel(footnote),
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
      footnote: sheetFootnote,
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
