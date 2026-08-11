// SPDX-License-Identifier: Apache-2.0
/// Role management: `GET /roles`, `DELETE /roles/{id}`, plus the editor and
/// assignment sheets this screen opens. Requires MANAGE_ROLES.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../permissions.dart';
import '../../providers/admin_providers.dart';
import '../../providers/providers.dart';
import '../../routing/routes.dart';
import '../settings_screen_scaffold.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/run_guarded.dart';
import '../../widgets/settings_entity_row.dart';
import '../../widgets/settings_section_header.dart';
import 'role_assign_sheet.dart';
import 'role_editor_sheet.dart';

class RolesScreen extends ConsumerWidget {
  const RolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(roleChangeWatcherProvider);
    final roles = ref.watch(rolesProvider);

    return SettingsScreenScaffold(
      title: 'Roles',
      backTooltip: 'Back to Space settings',
      backFallback: Routes.spaceSettings,
      // Stays a scaffold action: the card only renders once loaded, and creating a role must stay reachable meanwhile.
      actions: [
        IconButton(
          icon: const Icon(AppIcons.add),
          tooltip: 'New role',
          onPressed: () => showRoleEditorSheet(context),
        ),
      ],
      child: AppAsyncView<List<api.Role>>(
        value: AppAsyncState(data: roles.valueOrNull, error: roles.error),
        center: false,
        errorMessage: 'Could not load roles.',
        onRetry: () => ref.invalidate(rolesProvider),
        isEmpty: (list) => list.isEmpty,
        emptyMessage: 'No roles yet. Create one with the + above.',
        // No section title: this screen is one group, so a header here would
        // only restate the app bar above it.
        data: (context, list) => SettingsSectionCard(
          children: [for (final role in list) _RoleRow(role: role)],
        ),
      ),
    );
  }
}

class _RoleRow extends ConsumerStatefulWidget {
  const _RoleRow({required this.role});

  final api.Role role;

  @override
  ConsumerState<_RoleRow> createState() => _RoleRowState();
}

class _RoleRowState extends ConsumerState<_RoleRow>
    with GuardedActionState<_RoleRow> {
  bool _busy = false;

  Future<void> _delete() async {
    final confirmed = await confirmDangerousAction(
      context,
      title: 'Delete "${widget.role.name}"?',
      message:
          'Members holding this role lose whatever it grants '
          'immediately. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final ok = await guard(
      whatFailed: 'delete the role',
      action: () => ref.read(apiProvider).deleteRole(widget.role.id),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) ref.invalidate(rolesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.role;
    final count = Perm.editable
        .where((e) => role.permissions.hasPermission(e.$1))
        .length;

    return SettingsEntityRow(
      headline: role.name,
      badge: role.isEveryone
          ? const AppBadge(variant: AppBadgeVariant.tag, label: 'Everyone')
          : null,
      details: [
        SettingsEntityDetail(
          // Named, not counted: "1 permission"/"0" on the two counts that read as bugs otherwise.
          role.permissions.hasPermission(Perm.administrator)
              ? 'Administrator, full access'
              : count == 0
              ? 'No permissions yet, edit to add some'
              : count == 1
              ? '1 permission'
              : '$count permissions',
        ),
      ],
      actions: [
        // @everyone can't be assigned or deleted; nulls reserve those slots so edit still lands at a shared x.
        SettingsEntityActions(
          children: [
            if (!role.isEveryone)
              AppIconButton(
                icon: AppIcons.assignRole,
                semanticLabel: 'Assign ${role.name} to members',
                onPressed: () => showRoleAssignSheet(context, role),
              )
            else
              null,
            AppIconButton(
              icon: AppIcons.edit,
              semanticLabel: 'Edit ${role.name}',
              onPressed: () => showRoleEditorSheet(context, role: role),
            ),
            if (!role.isEveryone)
              AppIconButton(
                icon: AppIcons.delete,
                semanticLabel: 'Delete ${role.name}',
                variant: AppIconButtonVariant.danger,
                onPressed: _busy ? null : _delete,
              )
            else
              null,
          ],
        ),
      ],
      error: actionError,
      onErrorDismiss: clearActionError,
    );
  }
}
