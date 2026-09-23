// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// [AnalyticsScreen]'s on/off control, split out of `analytics_screen.dart`
/// to keep that file under the review budget.
///
/// Off, this is [SettingsToggleRow] in full: label, switch and the whole
/// explanation, because deciding whether to turn analytics on is the one
/// moment that explanation is worth its height. On, it collapses to a
/// single row - the decision is already made, and a full paragraph would
/// otherwise sit above every real number on every future visit. The
/// explanation does not disappear: an info button reveals it in place,
/// collapsed again by default each time the toggle re-enables.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../../widgets/settings_section_header.dart';
import '../../widgets/settings_toggle_row.dart';

/// Full explanation, kept in one place: shown open in the off state and
/// reachable behind an info toggle once on.
const _analyticsDescription =
    'Off by default. Counts messages and reads this server\'s own memory '
    'use; never a per-member activity log. Turning this off hides the '
    'numbers below but keeps whatever was already recorded.';

class AnalyticsToggleHeader extends StatefulWidget {
  const AnalyticsToggleHeader({
    super.key,
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  final bool enabled;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  State<AnalyticsToggleHeader> createState() => _AnalyticsToggleHeaderState();
}

class _AnalyticsToggleHeaderState extends State<AnalyticsToggleHeader> {
  bool _explanationOpen = false;

  @override
  void didUpdateWidget(covariant AnalyticsToggleHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Starts collapsed again next time this turns on, not mid-expand.
    if (oldWidget.enabled && !widget.enabled) {
      _explanationOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return SettingsSectionCard(
        children: [
          SettingsToggleRow(
            label: 'Record Space analytics',
            description: _analyticsDescription,
            value: false,
            onChanged: widget.busy ? null : widget.onChanged,
            semanticLabel: 'Space analytics off',
          ),
        ],
      );
    }
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return SettingsSectionCard(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: AppListRow.heightFor(context)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Space analytics is on',
                  style: AppText.ui.copyWith(color: tokens.textPrimary),
                ),
              ),
              AppIconButton(
                icon: AppIcons.info,
                active: _explanationOpen,
                tooltip: _explanationOpen
                    ? 'Hide what this records'
                    : 'What this records',
                semanticLabel: _explanationOpen
                    ? 'Hide what Space analytics records'
                    : 'Show what Space analytics records',
                onPressed: () =>
                    setState(() => _explanationOpen = !_explanationOpen),
              ),
              const SizedBox(width: AppSpacing.s4),
              AppToggle(
                value: true,
                onChanged: widget.busy ? null : widget.onChanged,
                semanticLabel: 'Space analytics on',
              ),
            ],
          ),
        ),
        if (_explanationOpen) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            _analyticsDescription,
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
        ],
      ],
    );
  }
}
