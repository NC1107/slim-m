// SPDX-License-Identifier: Apache-2.0
/// Which build this is, for a tester to read off the device rather than
/// asking whoever is looking at it what they have installed.
///
/// Lives at the end of [PersonalSettingsScreen], not on a screen of its own:
/// it is neither about the account (it is the same for every account signed
/// into this install) nor about the Space (it is the same for every Space
/// this install ever connects to). Personal settings is the one screen every
/// signed-in caller can always reach regardless of permission, which is what
/// makes it, rather than Space settings, the one guaranteed to still carry
/// this along.
///
/// [SettingsSectionCard], its own bordered box with an "App" header, matching
/// every other section on the screen: it used to be a bare [Column] under a
/// now-deleted `SettingsGroupHeader`, the one personal-settings section with
/// no card around it, drawing a plain line where every sibling above it drew
/// a box.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';

import '../diagnostics/debug_log.dart';
import '../providers/providers.dart';
import '../routing/routes.dart';
import 'settings_section_header.dart';

class AppInfoSection extends ConsumerWidget {
  const AppInfoSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(appInfoProvider);
    final errors = ref.watch(debugLogProvider);

    return SettingsSectionCard(
      children: [
        AppListRow(
          leading: const Icon(AppIcons.info),
          label: 'Version',
          meta: info.when(
            data: (i) => '${i.version} (${i.buildNumber})',
            loading: () => 'Loading…',
            error: (e, _) => 'Unknown',
          ),
        ),
        AppListRow(
          leading: const Icon(AppIcons.activityLog),
          label: 'Debug log',
          meta: errors.isEmpty
              ? 'Nothing caught this session'
              : '${errors.length} caught this session',
          trailing: const Icon(AppIcons.chevronRight, size: AppSizes.icon16),
          onTap: () => context.push(Routes.debugLog),
        ),
      ],
    );
  }
}
