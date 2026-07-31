// SPDX-License-Identifier: Apache-2.0
/// Personal settings: what the account holder controls about themselves,
/// plus the app's own build information.
///
/// This is the one settings screen every signed-in caller can always reach,
/// regardless of permission; [SpaceSettingsScreen] is the deployment-level
/// counterpart, reached separately from the rail's Space menu and hidden
/// entirely for a caller holding none of its gating bits.
///
/// Nine sections used to sit in one scroll behind full-width dividers. They
/// are five panes now; see [SettingsPanesScaffold] for why, and note the
/// grouping rather than the count is the point: what you are, what a call
/// does, and who you have shut out are three different questions.
///
/// Voice is folded in here rather than living on its own screen, so mic level,
/// sensitivity, push-to-talk and share quality sit beside the account they
/// belong to instead of behind a second route nothing linked to twice.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import '../routing/routes.dart';
import '../widgets/app_info_section.dart';
import '../widgets/appearance_settings_section.dart';
import '../widgets/avatar_settings_section.dart';
import '../widgets/edit_display_name_sheet.dart';
import '../widgets/personal_account_sections.dart';
import '../widgets/personal_status_sections.dart';
import '../widgets/settings_panes.dart';
import 'voice_settings_screen.dart';
import '../widgets/user_avatar.dart';

class PersonalSettingsScreen extends ConsumerWidget {
  const PersonalSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsPanesScaffold(
      title: 'Settings',
      // Reached with go(), which replaces, so there is no stack to pop.
      backTooltip: 'Back to channels',
      backFallback: Routes.channels,
      header: const _WhoYouAre(),
      footer: const SignOutRow(),
      groups: [
        SettingsPaneGroup(
          label: 'You',
          panes: [
            SettingsPane(
              id: 'account',
              label: 'Account & presence',
              builder: (context) => const Column(
                children: [AvatarSettingsSection(), PresenceSection()],
              ),
            ),
            SettingsPane(
              id: 'appearance',
              label: 'Appearance',
              builder: (context) => const AppearanceSettingsSection(),
            ),
            SettingsPane(
              id: 'notifications',
              label: 'Notifications',
              builder: (context) => const NotificationsSection(),
            ),
          ],
        ),
        SettingsPaneGroup(
          label: 'Calls',
          panes: [
            SettingsPane(
              id: 'voice',
              label: 'Voice & screen share',
              builder: (context) => const VoiceSettingsBody(),
            ),
          ],
        ),
        SettingsPaneGroup(
          label: 'Safety',
          panes: [
            SettingsPane(
              id: 'devices',
              label: 'Devices',
              builder: (context) => const DevicesSection(),
            ),
            SettingsPane(
              id: 'blocked',
              label: 'Blocked',
              builder: (context) => const BlockedSection(),
            ),
          ],
        ),
        SettingsPaneGroup(
          label: 'About',
          panes: [
            SettingsPane(
              id: 'about',
              label: 'About slim-m',
              builder: (context) =>
                  const Column(children: [AppInfoSection(), AccountSection()]),
            ),
          ],
        ),
      ],
    );
  }
}

/// Who is signed in, above the nav. The one piece of identity that belongs on
/// the frame rather than in a pane: it says whose settings these are.
class _WhoYouAre extends ConsumerWidget {
  const _WhoYouAre();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final me = ref.watch(meProvider).valueOrNull;
    if (me == null) return const SizedBox.shrink();

    return Row(
      children: [
        UserAvatar(
          userId: me.id,
          avatarUpdatedAt: me.avatarUpdatedAt,
          name: me.displayName,
          size: 32,
        ),
        const SizedBox(width: AppSpacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      me.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.ui.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: AppWeights.medium,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  AppIconButton(
                    icon: AppIcons.edit,
                    semanticLabel: 'Edit display name',
                    tooltip: 'Edit display name',
                    size: AppIconButtonSize.sm,
                    onPressed: () => unawaited(
                      showEditDisplayNameSheet(context, me.displayName),
                    ),
                  ),
                ],
              ),
              Text(
                '@${me.username}',
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: tokens.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
