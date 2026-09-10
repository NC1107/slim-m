// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Who may use a module, answered where the module is.
///
/// Installing a module registers its permissions into the role editor and
/// grants them to nobody - deliberately, per decision 0021, since installing
/// something is not a decision about who may use it. But an administrator who
/// installs a module and then finds it appears nowhere has no reason to guess
/// that a role grant is the missing step, and ADMINISTRATOR deliberately does
/// not bypass a module's own permission. So the question is asked here, right
/// after the install, and stays reachable from the module afterwards.
///
/// One switch per role, covering every permission the module declares: a
/// module usually declares exactly one, and a role holding some but not all
/// of a multi-permission module's keys reads as off until it holds them all.
/// The per-key control still lives in the role editor for anyone who wants it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../providers/admin_providers.dart';
import '../../providers/app_launch.dart';
import '../../providers/code_block_runner.dart';
import '../../providers/providers.dart';
import '../../providers/slash_command.dart';
import '../../widgets/run_guarded.dart';
import '../../widgets/settings_section_header.dart';
import '../../widgets/settings_toggle_row.dart';

Future<void> showModuleAccessSheet(
  BuildContext context,
  api.DockManifest manifest,
) {
  return showAppSheet<void>(
    context,
    scrolls: true,
    builder: (context) => _ModuleAccessSheet(manifest: manifest),
  );
}

class _ModuleAccessSheet extends ConsumerStatefulWidget {
  const _ModuleAccessSheet({required this.manifest});

  final api.DockManifest manifest;

  @override
  ConsumerState<_ModuleAccessSheet> createState() => _ModuleAccessSheetState();
}

class _ModuleAccessSheetState extends ConsumerState<_ModuleAccessSheet>
    with GuardedActionState<_ModuleAccessSheet> {
  final Set<String> _pending = {};

  List<String> get _permKeys => [
    for (final p in widget.manifest.permissions) p.key,
  ];

  /// Whether a role holding [granted] holds every key this module declares.
  bool _holdsAll(List<api.GrantedModulePermission> granted) {
    final held = {
      for (final g in granted)
        if (g.moduleId == widget.manifest.id) g.permKey,
    };
    return _permKeys.isNotEmpty && _permKeys.every(held.contains);
  }

  Future<void> _set(api.Role role, bool value) async {
    setState(() => _pending.add(role.id));
    final client = ref.read(apiProvider);
    final ok = await guard(
      whatFailed: value
          ? 'give ${role.name} access to ${widget.manifest.name}'
          : 'take ${widget.manifest.name} away from ${role.name}',
      action: () async {
        for (final key in _permKeys) {
          if (value) {
            await client.grantModulePermission(
              roleId: role.id,
              moduleId: widget.manifest.id,
              permKey: key,
            );
          } else {
            await client.revokeModulePermission(
              roleId: role.id,
              moduleId: widget.manifest.id,
              permKey: key,
            );
          }
        }
      },
    );
    if (!mounted) return;
    setState(() => _pending.remove(role.id));
    if (ok) {
      ref.invalidate(roleModulePermissionsProvider(role.id));
      // A grant changes what the caller may reach, so discovery is stale at once.
      ref.invalidate(codeBlockRunnerProvider);
      ref.invalidate(slashCommandProvider);
      ref.invalidate(appLaunchProvider);
    }
  }

  String _summary() {
    final names = [for (final p in widget.manifest.permissions) p.name];
    if (names.isEmpty) {
      return 'This module declares no permission of its own, so everyone who '
          'can see a channel can already use it.';
    }
    if (names.length == 1) return 'Grants "${names.single}".';
    return 'Grants ${names.length} permissions: ${names.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final roles = ref.watch(rolesProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s16,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.s16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Who can use ${widget.manifest.name}?',
              style: AppText.heading.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.semi,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              _summary(),
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s16),
            AppAsyncView<List<api.Role>>(
              value: AppAsyncState(data: roles.valueOrNull, error: roles.error),
              center: false,
              errorMessage: 'Could not load the roles.',
              onRetry: () => ref.invalidate(rolesProvider),
              data: (context, list) => SettingsSectionCard(
                children: [
                  for (final role in list)
                    _RoleSwitch(
                      role: role,
                      busy: _pending.contains(role.id),
                      keysDeclared: _permKeys.isNotEmpty,
                      holdsAll: _holdsAll,
                      onChanged: (value) => _set(role, value),
                    ),
                ],
              ),
            ),
            if (actionError != null) ...[
              const SizedBox(height: AppSpacing.s8),
              AppErrorState(message: actionError!, onDismiss: clearActionError),
            ],
            const SizedBox(height: AppSpacing.s12),
            AppButton(
              label: 'Done',
              variant: AppButtonVariant.primary,
              full: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// One role's switch, watching that role's own grants so a toggle reflects
/// what the server actually holds rather than what was tapped.
class _RoleSwitch extends ConsumerWidget {
  const _RoleSwitch({
    required this.role,
    required this.busy,
    required this.keysDeclared,
    required this.holdsAll,
    required this.onChanged,
  });

  final api.Role role;
  final bool busy;
  final bool keysDeclared;
  final bool Function(List<api.GrantedModulePermission>) holdsAll;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final granted = ref.watch(roleModulePermissionsProvider(role.id));
    final ready = granted.hasValue && !busy && keysDeclared;
    return SettingsToggleRow(
      label: role.name,
      semanticLabel: 'Let ${role.name} use this module',
      value: holdsAll(granted.valueOrNull ?? const []),
      onChanged: ready ? onChanged : null,
    );
  }
}
