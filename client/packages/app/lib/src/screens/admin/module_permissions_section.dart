// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Module-declared permissions in the role editor: grantable rows alongside
/// the fixed bitmask `role_editor_sheet.dart` edits directly. Unlike that
/// bitmask, a toggle here calls `PUT`/`DELETE
/// /roles/{roleId}/module-permissions/{moduleId}/{permKey}` immediately
/// rather than waiting on the sheet's own save, since the two live behind
/// separate routes - see `docs/decisions/0021-modules-and-the-dock.md`'s
/// "Dynamic permissions".
///
/// Only ever mounted for an existing role: granting requires a `roleId`,
/// which a role being created does not have until its first save.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../providers/admin_providers.dart';
import '../../providers/providers.dart';
import '../../widgets/run_guarded.dart';

class ModulePermissionsSection extends ConsumerStatefulWidget {
  const ModulePermissionsSection({super.key, required this.roleId});

  final String roleId;

  @override
  ConsumerState<ModulePermissionsSection> createState() =>
      _ModulePermissionsSectionState();
}

class _ModulePermissionsSectionState
    extends ConsumerState<ModulePermissionsSection>
    with GuardedActionState<ModulePermissionsSection> {
  final Set<String> _pending = {};

  static String _keyFor(api.ModulePermission p) => '${p.moduleId}:${p.permKey}';

  Future<void> _toggle(api.ModulePermission perm, bool value) async {
    final key = _keyFor(perm);
    setState(() => _pending.add(key));
    final ok = await guard(
      whatFailed: value ? 'grant ${perm.name}' : 'revoke ${perm.name}',
      action: () => value
          ? ref
                .read(apiProvider)
                .grantModulePermission(
                  roleId: widget.roleId,
                  moduleId: perm.moduleId,
                  permKey: perm.permKey,
                )
          : ref
                .read(apiProvider)
                .revokeModulePermission(
                  roleId: widget.roleId,
                  moduleId: perm.moduleId,
                  permKey: perm.permKey,
                ),
    );
    if (!mounted) return;
    setState(() => _pending.remove(key));
    if (ok) ref.invalidate(roleModulePermissionsProvider(widget.roleId));
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(modulePermissionsProvider);
    final granted = ref.watch(roleModulePermissionsProvider(widget.roleId));

    return AppAsyncView<List<api.ModulePermission>>(
      value: AppAsyncState(data: catalog.valueOrNull, error: catalog.error),
      center: false,
      errorMessage: 'Could not load module permissions.',
      onRetry: () => ref.invalidate(modulePermissionsProvider),
      isEmpty: (list) => list.isEmpty,
      emptyMessage:
          'No installed module declares a permission yet. Install one from '
          'the Dock to see it here.',
      data: (context, catalog) {
        // Toggles stay disabled until the role's grants resolve, so a tap cannot fire against unknown state.
        final grantedKeys = (granted.valueOrNull ?? const [])
            .map((g) => '${g.moduleId}:${g.permKey}')
            .toSet();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final perm in catalog)
              _ModulePermissionRow(
                permission: perm,
                value: grantedKeys.contains(_keyFor(perm)),
                busy: granted.isLoading || _pending.contains(_keyFor(perm)),
                onChanged: (v) => _toggle(perm, v),
              ),
            if (actionError != null) ...[
              const SizedBox(height: AppSpacing.s8),
              AppErrorState(message: actionError!, onDismiss: clearActionError),
            ],
          ],
        );
      },
    );
  }
}

class _ModulePermissionRow extends StatelessWidget {
  const _ModulePermissionRow({
    required this.permission,
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final api.ModulePermission permission;
  final bool value;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  permission.name,
                  style: AppText.ui.copyWith(color: tokens.textPrimary),
                ),
                Text(
                  permission.moduleName,
                  style: AppText.caption.copyWith(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
          AppToggle(
            value: value,
            onChanged: busy ? null : onChanged,
            semanticLabel: '${permission.name} (${permission.moduleName})',
          ),
        ],
      ),
    );
  }
}
