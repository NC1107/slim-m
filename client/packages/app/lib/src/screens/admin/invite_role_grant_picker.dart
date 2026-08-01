// SPDX-License-Identifier: Apache-2.0
/// Choosing the role an invite grants, offered only when the caller could
/// actually create one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../permissions.dart';
import '../../providers/admin_providers.dart';

/// The role picker, or nothing at all.
///
/// Absent rather than disabled for a caller without MANAGE_ROLES: the server
/// refuses that combination outright, and a control that can only fail is the
/// thing this codebase keeps taking back out.
class InviteRoleGrantPicker extends ConsumerWidget {
  const InviteRoleGrantPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  /// The chosen role id, or null for "grants no role".
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(myPermissionsProvider);
    if (!permissions.hasPermission(Perm.manageRoles)) {
      return const SizedBox.shrink();
    }

    final roles = ref.watch(rolesProvider);
    return roles.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (all) {
        // Only what this caller could grant: the server refuses a role
        // carrying a bit they do not hold, so offering it invites a 403.
        final grantable = all
            .where((r) => !r.isEveryone)
            .where((r) => permissions.hasPermission(r.permissions))
            .toList();
        if (grantable.isEmpty) return const SizedBox.shrink();

        final chosen = grantable.where((r) => r.id == selected).firstOrNull;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s12),
          child: AppListRow(
            label: 'Role granted',
            meta: chosen?.name ?? 'None',
            semanticLabel: 'Role granted, currently ${chosen?.name ?? 'none'}',
            trailing: const Icon(AppIcons.chevronRight, size: 16),
            onTap: () => _open(context, grantable),
          ),
        );
      },
    );
  }

  Future<void> _open(BuildContext context, List<api.Role> grantable) async {
    final picked = await showAppSheet<_Choice>(
      context,
      bare: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: AppSheetMenu(
          children: [
            const AppMenuLabel('Role granted on redemption'),
            AppMenuItem(
              label: 'None',
              selected: selected == null,
              leading: selected == null ? AppIcons.check : null,
              onTap: () => Navigator.of(sheetContext).pop(const _Choice(null)),
            ),
            for (final role in grantable)
              AppMenuItem(
                label: role.name,
                selected: role.id == selected,
                leading: role.id == selected ? AppIcons.check : null,
                onTap: () => Navigator.of(sheetContext).pop(_Choice(role.id)),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onChanged(picked.value);
  }
}

/// A wrapper so "the sheet was dismissed" is distinguishable from "None was
/// chosen", which a bare nullable String cannot express through `pop`.
class _Choice {
  const _Choice(this.value);

  final String? value;
}
