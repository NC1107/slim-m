// SPDX-License-Identifier: Apache-2.0
/// Grants and revokes one role across members: `PUT`/`DELETE
/// /members/{userId}/roles/{roleId}`, both idempotent.
///
/// A member's held state is read off [api.UserProfile.roleIds], never the
/// names beside them: nothing in the schema requires role names to be unique,
/// so two roles called "mod" would both light up if this matched by name.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../permissions.dart';
import '../../providers/admin_providers.dart';
import '../../providers/member_presence.dart' show membersProvider;
import '../../providers/providers.dart';
import '../../widgets/run_guarded.dart';

Future<void> showRoleAssignSheet(BuildContext context, api.Role role) {
  return showAppSheet<void>(
    context,
    scrolls: true,
    builder: (context) => _RoleAssignSheet(role: role),
  );
}

class _RoleAssignSheet extends ConsumerStatefulWidget {
  const _RoleAssignSheet({required this.role});

  final api.Role role;

  @override
  ConsumerState<_RoleAssignSheet> createState() => _RoleAssignSheetState();
}

class _RoleAssignSheetState extends ConsumerState<_RoleAssignSheet>
    with GuardedActionState<_RoleAssignSheet> {
  Future<void> _toggle(api.UserProfile member, bool value) async {
    final client = ref.read(apiProvider);
    final ok = await guard(
      whatFailed: 'update the assignment',
      action: () => value
          ? client.assignRole(userId: member.id, roleId: widget.role.id)
          : client.unassignRole(userId: member.id, roleId: widget.role.id),
    );
    if (ok && mounted) ref.invalidate(membersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final members = ref.watch(membersProvider);
    final mine = ref.watch(myPermissionsProvider);
    // Mirrors the server's refusal, so the toggle cannot spring back.
    final grantable = mine.hasPermission(widget.role.permissions);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s8,
              AppSpacing.s16,
              AppSpacing.s8,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Assign "${widget.role.name}"',
                style: AppText.heading.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: AppWeights.semi,
                ),
              ),
            ),
          ),
          if (actionError case final error?)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s16,
                0,
                AppSpacing.s16,
                AppSpacing.s8,
              ),
              child: AppErrorState(message: error, onDismiss: clearActionError),
            ),
          Expanded(
            child: members.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Could not load members.',
                  style: AppText.body.copyWith(color: tokens.textSecondary),
                ),
              ),
              data: (list) => ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final member = list[i];
                  final has = member.roleIds.contains(widget.role.id);
                  return AppListRow(
                    leading: const Icon(AppIcons.account),
                    label: member.displayName,
                    meta: grantable
                        ? null
                        : 'Needs permissions you do not hold',
                    trailing: AppToggle(
                      value: has,
                      onChanged: grantable ? (v) => _toggle(member, v) : null,
                      semanticLabel:
                          'Assign ${widget.role.name} to ${member.displayName}',
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
