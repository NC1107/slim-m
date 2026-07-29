// SPDX-License-Identifier: Apache-2.0
/// Personal settings: what the account holder controls about themselves,
/// plus the app's own build information.
///
/// This is the one settings screen every signed-in caller can always reach,
/// regardless of permission; [SpaceSettingsScreen] is the deployment-level
/// counterpart, reached separately from the rail's Space menu and hidden
/// entirely for a caller holding none of its gating bits. See
/// [AppInfoSection] for why the build information lives on this screen
/// rather than a third one of its own.
library;

import 'package:flutter/material.dart';

import '../routing/routes.dart';
import 'settings_screen_scaffold.dart';
import '../widgets/app_info_section.dart';
import '../widgets/appearance_settings_section.dart';
import '../widgets/avatar_settings_section.dart';
import '../widgets/personal_account_sections.dart';
import '../widgets/personal_status_sections.dart';

class PersonalSettingsScreen extends StatelessWidget {
  const PersonalSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsScreenScaffold(
      title: 'Settings',
      // Reached with go(), which replaces, so there is no stack to pop.
      backTooltip: 'Back to channels',
      backFallback: Routes.channels,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          AvatarSettingsSection(),
          Divider(height: 1),
          AppearanceSettingsSection(),
          Divider(height: 1),
          PresenceSection(),
          Divider(height: 1),
          NotificationsSection(),
          Divider(height: 1),
          VoiceSection(),
          Divider(height: 1),
          DevicesSection(),
          Divider(height: 1),
          BlockedSection(),
          Divider(height: 1),
          AccountSection(),
          Divider(height: 1),
          AppInfoSection(),
        ],
      ),
    );
  }
}
