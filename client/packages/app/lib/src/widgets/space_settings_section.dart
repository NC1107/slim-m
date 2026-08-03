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
    permissions.hasPermission(Perm.manageServer) ||
    permissions.hasPermission(Perm.banMembers);

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
    final canBan = permissions.hasPermission(Perm.banMembers);

    final tokens = Theme.of(context).extension<AppTokens>()!;
    Widget chevron() => Icon(
      AppIcons.chevronRight,
      size: AppSizes.icon16,
      color: tokens.textSecondary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canModerate)
          AppListRow(
            label: 'Reports',
            leading: const Icon(AppIcons.report),
            trailing: chevron(),
            onTap: () => context.push(Routes.adminReports),
          ),
        if (canInvite)
          AppListRow(
            label: 'Invites',
            leading: const Icon(AppIcons.invite),
            trailing: chevron(),
            onTap: () => context.push(Routes.adminInvites),
          ),
        if (canManageRoles) ...[
          AppListRow(
            label: 'Roles',
            leading: const Icon(AppIcons.shield),
            trailing: chevron(),
            onTap: () => context.push(Routes.adminRoles),
          ),
          AppListRow(
            label: 'Channel permissions',
            leading: const Icon(AppIcons.permissions),
            trailing: chevron(),
            onTap: () => context.push(Routes.adminOverwrites),
          ),
        ],
        if (canBan)
          AppListRow(
            label: 'Removed members',
            leading: const Icon(AppIcons.signOut),
            trailing: chevron(),
            onTap: () => context.push(Routes.adminRemovedMembers),
          ),
        if (canManageServer) const JoinPolicyRow(),
        if (canManageServer)
          AppListRow(
            label: 'Emoji',
            leading: const Icon(AppIcons.smile),
            trailing: chevron(),
            onTap: () => context.push(Routes.adminEmoji),
          ),
      ],
    );
  }
}
