// SPDX-License-Identifier: Apache-2.0
/// Grants and revokes one role across members: `PUT`/`DELETE
/// /members/{userId}/roles/{roleId}`, both idempotent.
///
/// A member's held state is read off [api.UserProfile.roles], which is a
/// list of role *names*; two roles sharing a name would be indistinguishable
/// here, but nothing in the schema requires role names to be unique, so this
/// is a real (accepted) limitation rather than an oversight.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../providers/member_presence.dart' show membersProvider;
import '../../providers/providers.dart';

Future<void> showRoleAssignSheet(BuildContext context, api.Role role) {
  return showAppSheet<void>(
    context,
    scrolls: true,
    builder: (context) => _RoleAssignSheet(role: role),
  );
}

class _RoleAssignSheet extends ConsumerWidget {
  const _RoleAssignSheet({required this.role});

  final api.Role role;

  Future<void> _toggle(
    WidgetRef ref,
    BuildContext context,
    api.UserProfile member,
    bool value,
  ) async {
    final client = ref.read(apiProvider);
    try {
      if (value) {
        await client.assignRole(userId: member.id, roleId: role.id);
      } else {
        await client.unassignRole(userId: member.id, roleId: role.id);
      }
      if (context.mounted) ref.invalidate(membersProvider);
    } on api.ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update the assignment. ${e.message}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final members = ref.watch(membersProvider);

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
                'Assign "${role.name}"',
                style: AppText.heading.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: AppWeights.semi,
                ),
              ),
            ),
          ),
          Expanded(
            child: members.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Could not load members.',
                  style: TextStyle(color: tokens.textSecondary),
                ),
              ),
              data: (list) => ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final member = list[i];
                  final has = member.roles.contains(role.name);
                  return ListTile(
                    leading: const Icon(AppIcons.account),
                    title: Text(member.displayName),
                    subtitle: Text(
                      '@${member.username}',
                      style: TextStyle(color: tokens.textSecondary),
                    ),
                    trailing: AppToggle(
                      value: has,
                      onChanged: (v) => _toggle(ref, context, member, v),
                      semanticLabel:
                          'Assign ${role.name} to ${member.displayName}',
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
