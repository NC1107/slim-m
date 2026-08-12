// SPDX-License-Identifier: Apache-2.0
/// Everything that changes the Space rather than the person: the reports
/// queue, invites, roles, channel permission overwrites, who can join, and
/// the Space's custom emoji - as the pane groups [SpaceSettingsScreen]'s
/// nav-and-pane scaffold renders.
///
/// This used to be a single scroll of chevron rows, each pushing a separate
/// admin route, which read as a different app from personal settings'
/// nav-and-pane split and cost a full navigation to glance at any one area.
/// The panes embed the same admin surfaces beside the nav on a wide window;
/// each still names its route as [SettingsPane.compactRoute], so a phone
/// keeps the real, deep-linkable screens and the routes stay reachable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../permissions.dart';
import '../providers/admin_providers.dart';
import '../providers/channel_permissions.dart';
import '../routing/routes.dart';
import '../screens/admin/analytics_screen.dart';
import '../screens/admin/categories_screen.dart';
import '../screens/admin/channel_overwrites_screen.dart';
import '../screens/admin/emoji_screen.dart';
import '../screens/admin/invites_screen.dart';
import '../screens/admin/removed_members_screen.dart';
import '../screens/admin/reports_screen.dart';
import '../screens/admin/roles_screen.dart';
import 'join_policy_row.dart';
import 'settings_panes.dart';
import 'settings_section_header.dart';

/// Whether [permissions] carries any of the bits that gate a pane here.
/// Shared with the rail's Space menu, which must hide its own entry point on
/// exactly this condition rather than open onto a screen with nothing on it.
bool spaceSettingsReachable(int permissions) =>
    permissions.hasPermission(Perm.manageMessages) ||
    permissions.hasPermission(Perm.createInvite) ||
    permissions.hasPermission(Perm.manageRoles) ||
    permissions.hasPermission(Perm.manageServer) ||
    permissions.hasPermission(Perm.manageChannels) ||
    permissions.hasPermission(Perm.banMembers);

/// Each pane is gated on the server bit its surface requires, per `GET /me`'s
/// base permissions, rather than shown and left to answer 403: a member
/// without MANAGE_ROLES should not see role editing exists at all.
/// A group with none of its panes visible is dropped whole.
List<SettingsPaneGroup> spaceSettingsPaneGroups(
  BuildContext context,
  WidgetRef ref,
) {
  final permissions = ref.watch(myPermissionsProvider);
  final canModerate = permissions.hasPermission(Perm.manageMessages);
  final canInvite = permissions.hasPermission(Perm.createInvite);
  final canManageRoles = permissions.hasPermission(Perm.manageRoles);
  final canManageServer = permissions.hasPermission(Perm.manageServer);
  final canManageChannels = permissions.hasPermission(Perm.manageChannels);
  final canBan = permissions.hasPermission(Perm.banMembers);
  // Unlike Roles (deployment-wide), this pane also opens via one overwrite.
  final visibleChannels =
      ref.watch(myVisibleChannelsProvider).valueOrNull ?? const [];
  final canManageRolesAnywhere =
      canManageRoles ||
      visibleChannels.any(
        (c) => (c.permissions ?? 0).hasPermission(Perm.manageRoles),
      );

  final groups = [
    SettingsPaneGroup(
      label: 'Moderation',
      panes: [
        if (canModerate)
          SettingsPane(
            id: 'reports',
            label: 'Reports',
            icon: AppIcons.report,
            compactRoute: Routes.adminReports,
            // The queue pages its own list; see ReportsScreen's same pair.
            scrollable: false,
            padding: EdgeInsets.zero,
            builder: (_) => const ReportsPane(),
          ),
        if (canBan)
          SettingsPane(
            id: 'removed-members',
            label: 'Removed members',
            icon: AppIcons.signOut,
            compactRoute: Routes.adminRemovedMembers,
            builder: (_) => const RemovedMembersPane(),
          ),
      ],
    ),
    SettingsPaneGroup(
      label: 'Access',
      panes: [
        if (canInvite)
          SettingsPane(
            id: 'invites',
            label: 'Invites',
            icon: AppIcons.invite,
            compactRoute: Routes.adminInvites,
            builder: (_) => const InvitesPane(),
          ),
        if (canManageServer)
          SettingsPane(
            id: 'join-policy',
            label: 'Who can join',
            icon: AppIcons.members,
            builder: (_) => const SettingsSectionCard(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [JoinPolicyRow()],
            ),
          ),
      ],
    ),
    SettingsPaneGroup(
      label: 'Configuration',
      panes: [
        if (canManageRoles)
          SettingsPane(
            id: 'roles',
            label: 'Roles',
            icon: AppIcons.shield,
            compactRoute: Routes.adminRoles,
            actions: [rolesPaneCreateAction(context)],
            builder: (_) => const RolesPane(),
          ),
        if (canManageRolesAnywhere)
          SettingsPane(
            id: 'channel-permissions',
            label: 'Channel permissions',
            icon: AppIcons.permissions,
            compactRoute: Routes.adminOverwrites,
            builder: (_) => const ChannelOverwritesPane(),
          ),
        if (canManageChannels)
          SettingsPane(
            id: 'categories',
            label: 'Channel categories',
            icon: AppIcons.hash,
            compactRoute: Routes.adminCategories,
            builder: (_) => const CategoriesPane(),
          ),
        if (canManageServer)
          SettingsPane(
            id: 'emoji',
            label: 'Emoji',
            icon: AppIcons.smile,
            compactRoute: Routes.adminEmoji,
            builder: (_) => const EmojiPane(),
          ),
        if (canManageServer)
          SettingsPane(
            id: 'analytics',
            label: 'Analytics',
            icon: AppIcons.analytics,
            compactRoute: Routes.adminAnalytics,
            builder: (_) => const AnalyticsPane(),
          ),
      ],
    ),
  ];
  return [
    for (final group in groups)
      if (group.panes.isNotEmpty) group,
  ];
}
