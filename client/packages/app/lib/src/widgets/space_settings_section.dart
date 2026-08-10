// SPDX-License-Identifier: Apache-2.0
/// Everything that changes the Space rather than the person: the reports
/// queue, invites, roles, channel permission overwrites, who can join, and
/// the Space's custom emoji.
///
/// This is [SpaceSettingsScreen]'s whole body. Grouped into bordered
/// [SettingsSectionCard]s the same way a personal settings pane is, rather
/// than one bare column of rows under the app bar: every row here is a link
/// to a screen of its own instead of inline content, which is why this
/// screen is a single scroll rather than the nav-and-pane split personal
/// settings uses, but that navigation difference is not licence for the two
/// to read as different apps.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';

import '../permissions.dart';
import '../providers/admin_providers.dart';
import '../providers/channel_permissions.dart';
import '../routing/routes.dart';
import 'join_policy_row.dart';
import 'settings_section_header.dart';

/// Whether [permissions] carries any of the four bits that gate a row on
/// [SpaceSettingsSection]. Shared with the rail's Space menu, which must hide
/// its own entry point on exactly this condition rather than open onto a
/// screen with nothing on it.
bool spaceSettingsReachable(int permissions) =>
    permissions.hasPermission(Perm.manageMessages) ||
    permissions.hasPermission(Perm.createInvite) ||
    permissions.hasPermission(Perm.manageRoles) ||
    permissions.hasPermission(Perm.manageServer) ||
    permissions.hasPermission(Perm.manageChannels) ||
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
    final canManageChannels = permissions.hasPermission(Perm.manageChannels);
    final canBan = permissions.hasPermission(Perm.banMembers);
    // Unlike Roles (deployment-wide), this row also opens via one overwrite.
    final visibleChannels =
        ref.watch(myVisibleChannelsProvider).valueOrNull ?? const [];
    final canManageRolesAnywhere =
        canManageRoles ||
        visibleChannels.any(
          (c) => (c.permissions ?? 0).hasPermission(Perm.manageRoles),
        );

    final tokens = Theme.of(context).extension<AppTokens>()!;
    Widget chevron() => Icon(
      AppIcons.chevronRight,
      size: AppSizes.icon16,
      color: tokens.textSecondary,
    );

    // A group renders only when at least one of its rows does.
    final groups = <(String, List<Widget>)>[
      (
        'Moderation',
        [
          if (canModerate)
            AppListRow(
              label: 'Reports',
              leading: const Icon(AppIcons.report),
              trailing: chevron(),
              onTap: () => context.push(Routes.adminReports),
            ),
          if (canBan)
            AppListRow(
              label: 'Removed members',
              leading: const Icon(AppIcons.signOut),
              trailing: chevron(),
              onTap: () => context.push(Routes.adminRemovedMembers),
            ),
        ],
      ),
      (
        'Access',
        [
          if (canInvite)
            AppListRow(
              label: 'Invites',
              leading: const Icon(AppIcons.invite),
              trailing: chevron(),
              onTap: () => context.push(Routes.adminInvites),
            ),
          if (canManageServer) const JoinPolicyRow(),
        ],
      ),
      (
        'Configuration',
        [
          if (canManageRoles)
            AppListRow(
              label: 'Roles',
              leading: const Icon(AppIcons.shield),
              trailing: chevron(),
              onTap: () => context.push(Routes.adminRoles),
            ),
          if (canManageRolesAnywhere)
            AppListRow(
              label: 'Channel permissions',
              leading: const Icon(AppIcons.permissions),
              trailing: chevron(),
              onTap: () => context.push(Routes.adminOverwrites),
            ),
          if (canManageChannels)
            AppListRow(
              label: 'Channel categories',
              leading: const Icon(AppIcons.hash),
              trailing: chevron(),
              onTap: () => context.push(Routes.adminCategories),
            ),
          if (canManageServer)
            AppListRow(
              label: 'Emoji',
              leading: const Icon(AppIcons.smile),
              trailing: chevron(),
              onTap: () => context.push(Routes.adminEmoji),
            ),
          if (canManageServer)
            AppListRow(
              label: 'Analytics',
              leading: const Icon(AppIcons.analytics),
              trailing: chevron(),
              onTap: () => context.push(Routes.adminAnalytics),
            ),
        ],
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (title, rows) in groups)
          if (rows.isNotEmpty)
            SettingsSectionCard(title: title, children: rows),
      ],
    );
  }
}
