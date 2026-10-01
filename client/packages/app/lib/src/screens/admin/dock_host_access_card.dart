// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// "Access to approve": the host capabilities a module asks for, each with a
/// switch, so the admin decides what a module may do before it runs
/// (docs/decisions/0023-mediated-host-capabilities.md).
///
/// A capability the module declares but this client cannot describe is not
/// offered here: the host implements only the ones named below, so a switch for
/// anything else would approve nothing.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../../widgets/settings_section_header.dart';
import '../../widgets/settings_toggle_row.dart';

/// The host capabilities the server can grant, in the order they are listed.
const dockHostCapabilities = <String, (String, String)>{
  'kv.store': (
    'Remember data',
    'Keeps a small private store for this module: up to 256 entries and '
        '64 KB. No other module can read it, and uninstalling deletes it.',
  ),
  'message.post': (
    'Post messages',
    'Posts into a channel as whoever runs it, marked "via" this module. Only '
        'where that person could post, and rate limited.',
  ),
};

/// The capabilities among [declared] the host can grant, in listed order.
List<String> grantableHostCapabilities(Iterable<String> declared) => [
  for (final capability in dockHostCapabilities.keys)
    if (declared.contains(capability)) capability,
];

class DockHostAccessCard extends StatelessWidget {
  const DockHostAccessCard({
    super.key,
    required this.declared,
    required this.approved,
    required this.onChanged,
    required this.moduleName,
    this.reapprovePosting = false,
    this.enabled = true,
  });

  final List<String> declared;
  final Set<String> approved;
  final void Function(String capability, bool approved) onChanged;
  final String moduleName;

  /// Says the update needs "Post messages" approved again.
  final bool reapprovePosting;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final grantable = grantableHostCapabilities(declared);
    if (grantable.isEmpty) return const SizedBox.shrink();
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return SettingsSectionCard(
      title: 'Access to approve',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s8,
            AppSpacing.s4,
            AppSpacing.s8,
            AppSpacing.s8,
          ),
          child: Text(
            reapprovePosting
                ? 'This is a new build, so Post messages needs your approval '
                      'again. Other access carries over. Applied when you '
                      'update or save.'
                : 'Off unless you turn it on. Applied when you install or save.',
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
        ),
        for (final capability in grantable)
          SettingsToggleRow(
            label: dockHostCapabilities[capability]!.$1,
            description: dockHostCapabilities[capability]!.$2,
            value: approved.contains(capability),
            onChanged: enabled ? (v) => onChanged(capability, v) : null,
            semanticLabel:
                '${dockHostCapabilities[capability]!.$1} for $moduleName',
          ),
      ],
    );
  }
}
