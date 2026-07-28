// SPDX-License-Identifier: Apache-2.0
/// Space settings: reports, invites, roles, channel permissions, who can
/// join, and emoji. Reached only from the rail's Space menu, which hides
/// itself for a caller holding none of the four gating bits, so this screen
/// renders [SpaceSettingsSection]'s empty case only on a direct navigation.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';

import '../routing/routes.dart';
import '../widgets/space_settings_section.dart';

class SpaceSettingsScreen extends StatelessWidget {
  const SpaceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Space settings'),
        // Reached with go(), which replaces, so there is no stack to pop.
        leading: IconButton(
          icon: const Icon(AppIcons.back),
          tooltip: 'Back to channels',
          onPressed: () => context.go(Routes.channels),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(children: const [SpaceSettingsSection()]),
      ),
    );
  }
}
