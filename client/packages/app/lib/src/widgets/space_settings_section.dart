// SPDX-License-Identifier: Apache-2.0
/// Everything in settings that changes the Space rather than the person: the
/// reports queue, invites, roles, channel permission overwrites, and the
/// Space's custom emoji.
///
/// It owns the "Space" group header itself, so a caller with none of the
/// gating bits removes the whole group by returning nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';

import '../permissions.dart';
import '../providers/admin_providers.dart';
import '../routing/routes.dart';
import 'join_policy_row.dart';
import 'settings_section_header.dart';

/// Each row is gated on the server bit its screen requires, per `GET /me`'s
/// base permissions, rather than shown and left to answer 403: a member
/// without MANAGE_ROLES should not see role editing exists at all.
///
/// Hidden entirely, group header and divider included, for a caller with none
/// of the gating bits, so an ordinary member's settings screen holds nothing
/// but their own settings.
class SpaceSettingsSection extends ConsumerWidget {
  const SpaceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(myPermissionsProvider);
    final canModerate = permissions.hasPermission(Perm.manageMessages);
    final canInvite = permissions.hasPermission(Perm.createInvite);
    final canManageRoles = permissions.hasPermission(Perm.manageRoles);
    final canManageServer = permissions.hasPermission(Perm.manageServer);

    if (!canModerate && !canInvite && !canManageRoles && !canManageServer) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SettingsGroupHeader('Space'),
        const SizedBox(height: AppSpacing.s8),
        if (canModerate)
          ListTile(
            leading: const Icon(AppIcons.report),
            title: const Text('Reports'),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => context.push(Routes.adminReports),
          ),
        if (canInvite)
          ListTile(
            leading: const Icon(AppIcons.invite),
            title: const Text('Invites'),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => context.push(Routes.adminInvites),
          ),
        if (canManageRoles) ...[
          ListTile(
            leading: const Icon(AppIcons.shield),
            title: const Text('Roles'),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => context.push(Routes.adminRoles),
          ),
          ListTile(
            leading: const Icon(AppIcons.permissions),
            title: const Text('Channel permissions'),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => context.push(Routes.adminOverwrites),
          ),
        ],
        if (canManageServer) const JoinPolicyRow(),
        if (canManageServer)
          ListTile(
            leading: const Icon(AppIcons.smile),
            title: const Text('Emoji'),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => context.push(Routes.adminEmoji),
          ),
      ],
    );
  }
}
