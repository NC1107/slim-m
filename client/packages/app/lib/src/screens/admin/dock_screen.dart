// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The Dock: browsing and installing modules from the addons marketplace.
/// `GET /space/dock/modules` and `GET /space/dock/installed`. Requires
/// MANAGE_SERVER, the same bit `/space/settings` and every other pane in this
/// directory already require.
///
/// Read-only itself: opening a row is what leads to install, enable/disable
/// and uninstall, all on the module's own screen - see
/// `docs/decisions/0021-modules-and-the-dock.md`'s lifecycle. This mirrors
/// `analytics_screen.dart`/`storage_screen.dart`'s own shape: a scaffold plus
/// an `AppAsyncView` over a Space settings pane.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';

import '../../providers/admin_providers.dart';
import '../../routing/routes.dart';
import '../../widgets/settings_entity_row.dart';
import '../../widgets/settings_section_header.dart';
import '../settings_screen_scaffold.dart';

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
class DockPane extends ConsumerStatefulWidget {
  const DockPane({super.key});

  @override
  ConsumerState<DockPane> createState() => _DockPaneState();
}

class _DockPaneState extends ConsumerState<DockPane> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Name, id and summary, so a search for what a module *does* finds it and
  /// not only one for what it is called.
  bool _matches(api.DockIndexEntry entry, String needle) =>
      entry.name.toLowerCase().contains(needle) ||
      entry.id.toLowerCase().contains(needle) ||
      entry.summary.toLowerCase().contains(needle);

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final catalog = ref.watch(dockCatalogProvider);
    final needle = _query.text.trim().toLowerCase();
    return AppAsyncView<DockCatalog>(
      value: AppAsyncState(data: catalog.valueOrNull, error: catalog.error),
      center: false,
      errorMessage: 'Could not reach the module marketplace.',
      onRetry: () => ref.invalidate(dockCatalogProvider),
      isEmpty: (c) => c.entries.isEmpty,
      emptyMessage: 'No modules are published in the marketplace yet.',
      // No section title: this screen is one group, matching Roles' own choice.
      data: (context, catalog) {
        final shown = [
          for (final entry in catalog.entries)
            if (needle.isEmpty || _matches(entry, needle)) entry,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppInput(
              controller: _query,
              placeholder: 'Search modules',
              semanticLabel: 'Search modules',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.s12),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Text(
                  'No module matches "${_query.text.trim()}".',
                  style: AppText.body.copyWith(color: tokens.textSecondary),
                ),
              )
            else
              SettingsSectionCard(
                children: [
                  for (final entry in shown)
                    _ModuleRow(
                      entry: entry,
                      installed: catalog.installedFor(entry.id),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({required this.entry, required this.installed});

  final api.DockIndexEntry entry;

  /// This space's own install record for [entry], or null when it has never
  /// been docked here.
  final api.InstalledDockModule? installed;

  /// What this space has, against what the marketplace now offers.
  ///
  /// A version that differs is the whole update affordance on this screen:
  /// the row used to show the registry's version and the word "Installed"
  /// side by side, which reads as agreement even when they disagree.
  static AppBadge _stateBadge(
    api.DockIndexEntry entry,
    api.InstalledDockModule installed,
  ) {
    if (installed.version != entry.version) {
      return AppBadge(
        variant: AppBadgeVariant.warn,
        label: 'v${installed.version} · update',
      );
    }
    return AppBadge(
      variant: AppBadgeVariant.role,
      label: installed.enabled ? 'Installed' : 'Installed · Off',
    );
  }

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
      badge: installed == null ? null : _stateBadge(entry, installed),
      details: [
        SettingsEntityDetail('v${entry.version}'),
        SettingsEntityDetail(entry.summary, wrap: true),
      ],
      onTap: () => context.go(Routes.adminDockModule(entry.id)),
      onTapSemanticLabel: 'View ${entry.name}',
      // Decorative: the row itself is the control, so this points the way without being a second, smaller target.
      actions: [
        ExcludeSemantics(
          child: Icon(AppIcons.chevronRight, color: tokens.textSecondary),
        ),
      ],
    );
  }
}
