// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A module's full manifest, opened from [DockPane]: `GET
/// /space/dock/modules/{id}`, plus the install/enable/disable/uninstall
/// actions - `docs/decisions/0021-modules-and-the-dock.md`'s lifecycle in one
/// sheet.
///
/// Everything a module will add is shown before an admin ever installs it:
/// the permissions it registers into the role editor and the host
/// capabilities it asks for, so approval happens with the whole picture in
/// view rather than after the fact.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../providers/admin_providers.dart';
import '../../providers/code_block_runner.dart';
import '../../providers/slash_command.dart';
import '../../providers/providers.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/run_guarded.dart';
import 'dock_module_view.dart';

Future<void> showDockModuleSheet(BuildContext context, String moduleId) {
  return showAppSheet<void>(
    context,
    scrolls: true,
    builder: (context) => _DockModuleSheet(moduleId: moduleId),
  );
}

class _DockModuleSheet extends ConsumerStatefulWidget {
  const _DockModuleSheet({required this.moduleId});

  final String moduleId;

  @override
  ConsumerState<_DockModuleSheet> createState() => _DockModuleSheetState();
}

class _DockModuleSheetState extends ConsumerState<_DockModuleSheet>
    with GuardedActionState<_DockModuleSheet> {
  bool _busy = false;

  Future<void> _install(api.DockManifest manifest) async {
    setState(() => _busy = true);
    final ok = await guard(
      whatFailed: 'install ${manifest.name}',
      action: () => ref
          .read(apiProvider)
          .installDockModule(moduleId: manifest.id, version: manifest.version),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(dockCatalogProvider);
      ref.invalidate(modulePermissionsProvider);
    }
  }

  Future<void> _setEnabled(String name, bool enabled) async {
    setState(() => _busy = true);
    final ok = await guard(
      whatFailed: enabled ? 'enable $name' : 'disable $name',
      action: () => enabled
          ? ref.read(apiProvider).enableDockModule(widget.moduleId)
          : ref.read(apiProvider).disableDockModule(widget.moduleId),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(dockCatalogProvider);
      ref.invalidate(codeBlockRunnerProvider);
      ref.invalidate(slashCommandProvider);
    }
  }

  Future<void> _uninstall(String name) async {
    final confirmed = await confirmDangerousAction(
      context,
      title: 'Uninstall $name?',
      message:
          'Removes it from this space along with every permission it '
          'registered and every role grant of them. This cannot be undone.',
      confirmLabel: 'Uninstall',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final ok = await guard(
      whatFailed: 'uninstall $name',
      action: () => ref.read(apiProvider).uninstallDockModule(widget.moduleId),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(dockCatalogProvider);
      ref.invalidate(modulePermissionsProvider);
      ref.invalidate(codeBlockRunnerProvider);
      ref.invalidate(slashCommandProvider);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final manifest = ref.watch(dockManifestProvider(widget.moduleId));
    final installed = ref
        .watch(dockCatalogProvider)
        .valueOrNull
        ?.installedFor(widget.moduleId);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s16,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.s16,
      ),
      child: SingleChildScrollView(
        child: AppAsyncView<api.DockManifest>(
          value: AppAsyncState(
            data: manifest.valueOrNull,
            error: manifest.error,
          ),
          center: false,
          errorMessage: 'Could not load this module.',
          onRetry: () => ref.invalidate(dockManifestProvider(widget.moduleId)),
          data: (context, m) => DockManifestView(
            manifest: m,
            installed: installed,
            busy: _busy,
            error: actionError,
            onErrorDismiss: clearActionError,
            onInstall: () => _install(m),
            onSetEnabled: (v) => _setEnabled(m.name, v),
            onUninstall: () => _uninstall(m.name),
          ),
        ),
      ),
    );
  }
}
