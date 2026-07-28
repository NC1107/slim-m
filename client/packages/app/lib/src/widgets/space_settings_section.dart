// SPDX-License-Identifier: Apache-2.0
/// Everything that changes the Space rather than the person: the reports
/// queue, invites, roles, channel permission overwrites, who can join, and
/// the Space's custom emoji.
///
/// This is [SpaceSettingsScreen]'s whole body, not a section sharing a screen
/// with personal settings, so it owns no group header or divider of its own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';

import '../permissions.dart';
import '../providers/admin_providers.dart';
import '../routing/routes.dart';
import 'join_policy_row.dart';

/// Whether [permissions] carries any of the four bits that gate a row on
/// [SpaceSettingsSection]. Shared with the rail's Space menu, which must hide
/// its own entry point on exactly this condition rather than open onto a
/// screen with nothing on it.
bool spaceSettingsReachable(int permissions) =>
    permissions.hasPermission(Perm.manageMessages) ||
    permissions.hasPermission(Perm.createInvite) ||
    permissions.hasPermission(Perm.manageRoles) ||
    permissions.hasPermission(Perm.manageServer);

/// Each row is gated on the server bit its screen requires, per `GET /me`'s
/// base permissions, rather than shown and left to answer 403: a member
/// without MANAGE_ROLES should not see role editing exists at all.
///
/// Hidden entirely for a caller with none of the gating bits, so this screen
/// holds nothing at all rather than an empty list under a bare app bar; the
/// rail's Space menu hides its own entry point on the same condition, so this
/// case is reachable only by a direct navigation, not by anything in the UI.
class SpaceSettingsSection extends ConsumerWidget {
  const SpaceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(myPermissionsProvider);
    if (!spaceSettingsReachable(permissions)) {
      return const SizedBox.shrink();
    }
    final canModerate = permissions.hasPermission(Perm.manageMessages);
    final canInvite = permissions.hasPermission(Perm.createInvite);
    final canManageRoles = permissions.hasPermission(Perm.manageRoles);
    final canManageServer = permissions.hasPermission(Perm.manageServer);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
