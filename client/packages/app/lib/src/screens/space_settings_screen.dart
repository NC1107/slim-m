// SPDX-License-Identifier: Apache-2.0
/// Space settings: reports, invites, roles, channel permissions, who can
/// join, and emoji. Reached only from the rail's Space menu, which hides
/// itself for a caller holding none of the four gating bits, so this screen
/// renders [SpaceSettingsSection]'s empty case only on a direct navigation.
library;

import 'package:flutter/material.dart';

import '../routing/routes.dart';
import 'settings_screen_scaffold.dart';
import '../widgets/space_settings_section.dart';

class SpaceSettingsScreen extends StatelessWidget {
  const SpaceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsScreenScaffold(
      title: 'Space settings',
      // Reached with go(), which replaces, so there is no stack to pop.
      backTooltip: 'Back to channels',
      backFallback: Routes.channels,
      // Default padding, matching a personal settings pane's own ListView.
      child: SpaceSettingsSection(),
    );
  }
}
