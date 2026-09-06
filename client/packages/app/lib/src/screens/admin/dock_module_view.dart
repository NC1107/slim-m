// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The read side of [DockManifestView]: a manifest's own summary, the
/// permissions it will add, the capabilities it asks for, and the
/// install/enable-disable/uninstall controls - split out of
/// `dock_module_sheet.dart` purely for that file's line budget, the same
/// reasoning `analytics_charts.dart` split off `analytics_screen.dart` on.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../widgets/attachment_view.dart' show formatByteSize;
import '../../widgets/settings_section_header.dart';
import '../../widgets/settings_toggle_row.dart';

/// A module's manifest, plus the lifecycle action appropriate to
/// [installed]'s state: install when null, otherwise an enable/disable
/// toggle and an uninstall button.
class DockManifestView extends StatelessWidget {
  const DockManifestView({
    super.key,
    required this.manifest,
    required this.installed,
    required this.busy,
    required this.error,
    required this.onErrorDismiss,
    required this.onInstall,
    required this.onSetEnabled,
    required this.onUninstall,
  });

  final api.DockManifest manifest;
  final api.InstalledDockModule? installed;
  final bool busy;
  final String? error;
  final VoidCallback onErrorDismiss;
  final VoidCallback onInstall;
  final ValueChanged<bool> onSetEnabled;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(AppIcons.dock, color: tokens.textSecondary),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                manifest.name,
                style: AppText.heading.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: AppWeights.semi,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          manifest.author == null
              ? 'v${manifest.version}'
              : 'v${manifest.version} · ${manifest.author}',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s12),
        Text(
          manifest.summary,
          style: AppText.body.copyWith(color: tokens.textPrimary),
        ),
        const SizedBox(height: AppSpacing.s16),
        _PermissionsCard(permissions: manifest.permissions),
        const SizedBox(height: AppSpacing.s16),
        _CapabilitiesCard(manifest: manifest),
        const SizedBox(height: AppSpacing.s16),
        _ActionsCard(
          manifest: manifest,
          installed: installed,
          busy: busy,
          onInstall: onInstall,
          onSetEnabled: onSetEnabled,
          onUninstall: onUninstall,
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.s8),
          AppErrorState(message: error!, onDismiss: onErrorDismiss),
        ],
      ],
    );
  }
}

/// What installing registers into this space's role editor, shown before
/// install rather than discovered afterward - see decision 0021's "Dynamic
/// permissions".
class _PermissionsCard extends StatelessWidget {
  const _PermissionsCard({required this.permissions});

  final List<api.DockPermission> permissions;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    if (permissions.isEmpty) {
      return SettingsSectionCard(
        title: 'Permissions this will add',
        children: [
          Text(
            'None. This module adds no grantable permission.',
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
        ],
      );
    }
    return SettingsSectionCard(
      title: 'Permissions this will add',
      children: [
        for (final p in permissions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: AppText.body.copyWith(color: tokens.textPrimary),
                ),
                Text(
                  p.description,
                  style: AppText.caption.copyWith(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// What a module asks the host for, and its runtime ceilings - the other
/// half of what an admin approves at install, alongside the permissions
/// above.
class _CapabilitiesCard extends StatelessWidget {
  const _CapabilitiesCard({required this.manifest});

  final api.DockManifest manifest;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final limits = manifest.runtime.limits;
    return SettingsSectionCard(
      title: 'Capabilities this asks for',
      children: [
        if (manifest.capabilities.isEmpty)
          Text(
            'None.',
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          )
        else
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              for (final capability in manifest.capabilities)
                AppBadge(variant: AppBadgeVariant.tag, label: capability),
            ],
          ),
        const SizedBox(height: AppSpacing.s12),
        Text(
          'Runtime: ${manifest.runtime.backend}'
          '${_limitsSummary(limits)}',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
  }

  static String _limitsSummary(api.DockLimits limits) {
    final parts = <String>[
      if (limits.memoryMb != null)
        formatByteSize(limits.memoryMb! * 1024 * 1024),
      if (limits.wallMs != null) '${limits.wallMs} ms',
      if (limits.fuel != null) '${limits.fuel} fuel',
    ];
    return parts.isEmpty ? '' : ' · ${parts.join(' · ')}';
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({
    required this.manifest,
    required this.installed,
    required this.busy,
    required this.onInstall,
    required this.onSetEnabled,
    required this.onUninstall,
  });

  final api.DockManifest manifest;
  final api.InstalledDockModule? installed;
  final bool busy;
  final VoidCallback onInstall;
  final ValueChanged<bool> onSetEnabled;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final installed = this.installed;
    if (installed == null) {
      return AppButton(
        label: busy ? 'Installing...' : 'Install v${manifest.version}',
        variant: AppButtonVariant.primary,
        full: true,
        disabled: busy,
        onPressed: onInstall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionCard(
          children: [
            SettingsToggleRow(
              label: 'Enabled',
              description:
                  'Off leaves it installed but inactive: its config and '
                  'permission grants stay in place.',
              value: installed.enabled,
              onChanged: busy ? null : onSetEnabled,
              semanticLabel: installed.enabled
                  ? '${manifest.name} enabled'
                  : '${manifest.name} disabled',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        AppButton(
          label: 'Uninstall',
          variant: AppButtonVariant.danger,
          full: true,
          disabled: busy,
          onPressed: onUninstall,
        ),
      ],
    );
  }
}
