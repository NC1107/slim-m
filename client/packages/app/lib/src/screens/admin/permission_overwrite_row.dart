// SPDX-License-Identifier: Apache-2.0
/// One permission's three-way state in a channel overwrite: inherit
/// (neither bit set), allow (forced on), or deny (forced off). Split out of
/// `channel_overwrites_screen.dart` to keep that file under budget.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// Matches [OverwriteState.deny]'s index, so a caller can read the selected
/// segment straight back into the tri-state this represents.
enum OverwriteState { inherit, allow, deny }

class PermissionOverwriteRow extends StatelessWidget {
  const PermissionOverwriteRow({
    super.key,
    required this.label,
    required this.value,
    required this.allowEnabled,
    required this.onChanged,
  });

  final String label;
  final OverwriteState value;

  /// Whether "Allow" is offered at all: the server refuses an `allow` bit
  /// the caller does not hold themselves, so this stays off the caller's own
  /// base permission set. "Deny" carries no such check and is always
  /// offered.
  final bool allowEnabled;
  final ValueChanged<OverwriteState> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final options = [
      const AppSegmentedOption(label: 'Inherit'),
      // Dimmed rather than merely inert: the server refuses granting a bit
      // the caller does not hold, so it must not look available.
      AppSegmentedOption(label: 'Allow', disabled: !allowEnabled),
      const AppSegmentedOption(label: 'Deny'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.ui.copyWith(color: tokens.textPrimary)),
          const SizedBox(height: AppSpacing.s4),
          AppSegmentedControl.inline(
            semanticLabel: label,
            options: options,
            selectedIndex: value.index,
            // The option itself wires no tap when disabled, so nothing to
            // guard against here.
            onSegmentSelected: (i) => onChanged(OverwriteState.values[i]),
          ),
        ],
      ),
    );
  }
}
