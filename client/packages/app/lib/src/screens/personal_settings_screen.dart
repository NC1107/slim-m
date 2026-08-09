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
///
/// Who you are, and the rename affordance for it, used to float above the nav
/// as its own unlabelled block - editable, yet outside every named section,
/// so "rename yourself" read as belonging to nothing. It lives inside
/// [AvatarSettingsSection]'s own "Profile" card now, which is what the
/// "Account & presence" pane opens onto, and each pane in the nav carries a
/// leading icon the way [SpaceSettingsSection]'s rows already do.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../routing/routes.dart';
import '../widgets/app_info_section.dart';
import '../widgets/appearance_settings_section.dart';
import '../widgets/avatar_settings_section.dart';
import '../widgets/personal_account_sections.dart';
import '../widgets/personal_status_sections.dart';
import '../widgets/settings_panes.dart';
import 'voice_settings_screen.dart';

class PersonalSettingsScreen extends StatelessWidget {
  const PersonalSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPanesScaffold(
      title: 'Settings',
      // Reached with go(), which replaces, so there is no stack to pop.
      backTooltip: 'Back to channels',
      backFallback: Routes.channels,
      footer: const SignOutRow(),
      groups: [
        SettingsPaneGroup(
          label: 'You',
          panes: [
            SettingsPane(
              id: 'account',
              label: 'Account & presence',
              icon: AppIcons.account,
              builder: (context) => const Column(
                children: [AvatarSettingsSection(), PresenceSection()],
              ),
            ),
            SettingsPane(
              id: 'appearance',
              label: 'Appearance',
              icon: AppIcons.appearance,
              builder: (context) => const AppearanceSettingsSection(),
            ),
            SettingsPane(
              id: 'notifications',
              label: 'Notifications',
              icon: AppIcons.notificationsOn,
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
              icon: AppIcons.voice,
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
              icon: AppIcons.devices,
              builder: (context) => const DevicesSection(),
            ),
            SettingsPane(
              id: 'blocked',
              label: 'Blocked',
              icon: AppIcons.revoke,
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
              icon: AppIcons.info,
              builder: (context) =>
                  const Column(children: [AppInfoSection(), AccountSection()]),
            ),
          ],
        ),
      ],
    );
  }
}
