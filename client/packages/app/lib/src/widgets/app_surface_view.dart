// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A launched app, rendered inline in its message as the module's interactive,
/// shared surface. The message says only which `(moduleId, command)` it
/// launched (see [api.AppSurface]); the surface itself is the module's own
/// output, run and stored against this message's block 0 through the shared
/// code-run route - exactly the machinery a run fenced code block uses, so
/// every viewer sees the same evolving surface and every step is shared.
///
/// This file names no module: it launches whatever the message carries and
/// renders whatever comes back, per docs/decisions/0021-modules-and-the-dock's
/// module-agnostic principle. A non-scene output still renders, as text, the
/// same way [ModuleCommandOutput] handles any command result.
///
/// On mount, if no run is stored yet, it runs the command once (empty input, so
/// a well-behaved app returns its initial frame); a later viewer just reads the
/// stored run. Every follow-up action (step, tap, play) goes back through the
/// same shared route from within [ModuleCommandOutput].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/message_extras.dart';
import '../providers/providers.dart';
import 'module_command_output.dart';
import 'run_guarded.dart';

/// The fenced-block index an app surface stores its shared state at. An app
/// message has no fenced blocks, so block 0 is always free and always its.
const _appBlockIndex = 0;

class AppSurfaceView extends ConsumerStatefulWidget {
  const AppSurfaceView({
    super.key,
    required this.messageId,
    required this.surface,
    required this.title,
  });

  final String messageId;
  final api.AppSurface surface;

  /// A human label for the app, shown as the surface's header. Falls back to
  /// the module id when discovery has no friendlier name.
  final String title;

  @override
  ConsumerState<AppSurfaceView> createState() => _AppSurfaceViewState();
}

class _AppSurfaceViewState extends ConsumerState<AppSurfaceView>
    with GuardedActionState<AppSurfaceView> {
  bool _running = false;
  bool _autoRan = false;

  api.CodeRun? _sharedRun() {
    final runs =
        ref.watch(
          messageExtrasProvider.select((m) => m[widget.messageId]?.codeRuns),
        ) ??
        const <api.CodeRun>[];
    for (final run in runs) {
      if (run.blockIndex == _appBlockIndex) return run;
    }
    return null;
  }

  Future<void> _run() async {
    setState(() => _running = true);
    await guard(
      whatFailed: 'launch this app',
      action: () async {
        await ref
            .read(apiProvider)
            .runCodeBlock(
              messageId: widget.messageId,
              blockIndex: _appBlockIndex,
              moduleId: widget.surface.moduleId,
              command: widget.surface.command,
              // A launch takes no argument; a well-behaved app returns its initial frame for empty input.
              input: '',
            );
      },
    );
    if (!mounted) return;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final sharedRun = _sharedRun();
    // First viewer with no stored run kicks it off once; the broadcast then feeds every viewer, including this one, through the shared cache.
    if (sharedRun == null && !_running && !_autoRan && actionError == null) {
      _autoRan = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run();
      });
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s8),
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                AppIcons.dock,
                size: AppSizes.icon16,
                color: tokens.textSecondary,
              ),
              const SizedBox(width: AppSpacing.s4),
              Text(
                widget.title,
                style: AppText.micro.copyWith(color: tokens.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          if (actionError != null)
            AppErrorState(message: actionError!, onDismiss: clearActionError)
          else if (sharedRun != null)
            ModuleCommandOutput(
              result: _asResult(sharedRun),
              moduleId: widget.surface.moduleId,
              command: widget.surface.command,
              messageId: widget.messageId,
              blockIndex: _appBlockIndex,
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.s8),
              child: SizedBox(
                width: AppSizes.icon20,
                height: AppSizes.icon20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  /// A [CodeRun]'s single `output` is the module's output when it succeeded, or
  /// its error otherwise - the same split [ModuleCommandOutput] renders.
  static api.RunModuleCommandResult _asResult(api.CodeRun run) =>
      api.RunModuleCommandResult(
        ok: run.ok,
        output: run.ok ? run.output : null,
        error: run.ok ? null : run.output,
      );
}
