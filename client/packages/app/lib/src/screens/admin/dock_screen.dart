// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The Dock: browsing and installing modules from the addons marketplace.
/// `GET /space/dock/modules` and `GET /space/dock/installed`. Requires
/// MANAGE_SERVER, the same bit `/space/settings` and every other pane in this
/// directory already require.
///
/// Read-only itself: opening a row is what leads to install, enable/disable
/// and uninstall, all in [showDockModuleSheet] - see
/// `docs/decisions/0021-modules-and-the-dock.md`'s lifecycle. This mirrors
/// `analytics_screen.dart`/`storage_screen.dart`'s own shape: a scaffold plus
/// an `AppAsyncView` over a Space settings pane.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../providers/admin_providers.dart';
import '../../routing/routes.dart';
import '../../widgets/settings_entity_row.dart';
import '../../widgets/settings_section_header.dart';
import '../settings_screen_scaffold.dart';
import 'dock_module_sheet.dart';

class DockScreen extends StatelessWidget {
  const DockScreen({super.key});

  @override
  Widget build(BuildContext context) => const SettingsScreenScaffold(
    title: 'Dock',
    backTooltip: 'Back to Space settings',
    backFallback: Routes.spaceSettings,
    child: DockPane(),
  );
}

/// The module list itself, embeddable as a Space settings pane as well as
/// routed.
class DockPane extends ConsumerWidget {
  const DockPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(dockCatalogProvider);
    return AppAsyncView<DockCatalog>(
      value: AppAsyncState(data: catalog.valueOrNull, error: catalog.error),
      center: false,
      errorMessage: 'Could not reach the module marketplace.',
      onRetry: () => ref.invalidate(dockCatalogProvider),
      isEmpty: (c) => c.entries.isEmpty,
      emptyMessage: 'No modules are published in the marketplace yet.',
      // No section title: this screen is one group, matching Roles' own choice.
      data: (context, catalog) => SettingsSectionCard(
        children: [
          for (final entry in catalog.entries)
            _ModuleRow(entry: entry, installed: catalog.installedFor(entry.id)),
        ],
      ),
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({required this.entry, required this.installed});

  final api.DockIndexEntry entry;

  /// This space's own install record for [entry], or null when it has never
  /// been docked here.
  final api.InstalledDockModule? installed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final installed = this.installed;
    return SettingsEntityRow(
      // Accent leading when installed, so it reads as installed down the list at a glance, not only from its badge.
      leading: Icon(
        AppIcons.dock,
        color: installed == null ? null : tokens.accent,
      ),
      headline: entry.name,
      badge: installed == null
          ? null
          : AppBadge(
              variant: AppBadgeVariant.role,
              label: installed.enabled ? 'Installed' : 'Installed · Off',
            ),
      details: [
        SettingsEntityDetail('v${entry.version}'),
        SettingsEntityDetail(entry.summary, wrap: true),
      ],
      actions: [
        AppIconButton(
          icon: AppIcons.chevronRight,
          semanticLabel: 'View ${entry.name}',
          onPressed: () => showDockModuleSheet(context, entry.id),
        ),
      ],
    );
  }
}
