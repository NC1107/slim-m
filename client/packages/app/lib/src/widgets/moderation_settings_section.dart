// SPDX-License-Identifier: Apache-2.0
/// Moderation and administration: the reports queue, invite management,
/// roles, and channel permission overwrites.
///
/// Moved out of `settings_screen.dart` unchanged, to get that file back under
/// the project's 500-line hard limit before another section was added to it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';

import '../permissions.dart';
import '../providers/admin_providers.dart';
import '../routing/routes.dart';
import 'settings_section_header.dart';

/// Each row is gated on the server bit its screen requires, per `GET /me`'s
/// base permissions, rather than shown and left to answer 403: a member
/// without MANAGE_ROLES should not see role editing exists at all.
///
/// Hidden entirely, divider included, for a caller with none of the four
/// bits, so an ordinary member's settings screen looks exactly as it did
/// before this section existed.
class ModerationSettingsSection extends ConsumerWidget {
  const ModerationSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(myPermissionsProvider);
    final canModerate = permissions.hasPermission(Perm.manageMessages);
    final canInvite = permissions.hasPermission(Perm.createInvite);
    final canManageRoles = permissions.hasPermission(Perm.manageRoles);

    if (!canModerate && !canInvite && !canManageRoles) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SettingsSectionHeader(
          'Community management',
          description: 'Only shown for what your roles let you do here.',
        ),
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
      ],
    );
  }
}
