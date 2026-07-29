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
import '../../routing/close_screen.dart';
import '../../widgets/confirm_dialog.dart';
import 'role_assign_sheet.dart';
import 'role_editor_sheet.dart';

class RolesScreen extends ConsumerWidget {
  const RolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(rolesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roles'),
        leading: BackToButton(
          tooltip: 'Back to Space settings',
          fallback: Routes.spaceSettings,
        ),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.add),
            tooltip: 'New role',
            onPressed: () => showRoleEditorSheet(context),
          ),
        ],
      ),
      // top: false because the AppBar already clears the status bar.
      body: AppContentColumn(
        child: SafeArea(
          top: false,
          child: roles.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => const Center(child: Text('Could not load roles.')),
            // Said, not blank: an empty page under a bare app bar reads as
            // broken, and the sibling admin lists all name their empty state.
            data: (list) => list.isEmpty
                ? const Center(
                    child: Text('No roles yet. Create one with the + above.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.s8),
                    itemBuilder: (context, i) => _RoleCard(role: list[i]),
                  ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends ConsumerStatefulWidget {
  const _RoleCard({required this.role});

  final api.Role role;

  @override
  ConsumerState<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends ConsumerState<_RoleCard> {
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
    try {
      await ref.read(apiProvider).deleteRole(widget.role.id);
      if (context.mounted) ref.invalidate(rolesProvider);
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the role. ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final role = widget.role;
    final count = Perm.editable
        .where((e) => role.permissions.hasPermission(e.$1))
        .length;

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      role.name,
                      style: TextStyle(color: tokens.textPrimary),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    if (role.isEveryone)
                      const AppBadge(
                        variant: AppBadgeVariant.tag,
                        label: 'Everyone',
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  // Named, not counted, for the two counts that read as bugs:
                  // "1 permission" on the most powerful role, "0" on a fresh one.
                  role.permissions.hasPermission(Perm.administrator)
                      ? 'Administrator, full access'
                      : count == 0
                      ? 'No permissions yet, edit to add some'
                      : count == 1
                      ? '1 permission'
                      : '$count permissions',
                  style: AppText.caption.copyWith(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
          AppIconButton(
            icon: AppIcons.assignRole,
            semanticLabel: 'Assign ${role.name} to members',
            onPressed: () => showRoleAssignSheet(context, role),
          ),
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
            // An empty slot the width of the button it stands in for, so the
            // assign and edit columns land at the same x on every row.
            SizedBox(
              width: AppTouchTargets.of(context)
                  ? AppSizes.rowTouch
                  : AppSizes.rowPointer,
            ),
        ],
      ),
    );
  }
}
