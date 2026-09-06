// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A fenced code block plus its optional "Run" affordance and, once run, its
/// output rendered inline below - notebook-style, monospace, clearly
/// delimited from the code above it.
///
/// The affordance itself is driven entirely by [codeBlockRunnerProvider] and
/// [matchCodeBlockRunner]: this file has no notion of what running code
/// means, only of "match this block's own language tag to a discovered
/// runner, then run whatever (module_id, command) that runner named" - see
/// docs/decisions/0021-modules-and-the-dock.md's module-agnostic principle.
///
/// Output is shared when the block has a [messageId]: Run posts to
/// `runCodeBlock`, which stores the result against `(messageId, blockIndex)`
/// and broadcasts it, so everyone viewing the message sees the latest run
/// inline (read here from [messageExtrasProvider]) without rerunning it - a
/// long job runs once for all. Without a [messageId] (a forwarded body, a
/// test) it falls back to the old per-viewer ephemeral run.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/code_block_runner.dart';
import '../providers/message_extras.dart';
import '../providers/providers.dart';
import 'message_code_lexer.dart';
import 'module_command_output.dart';
import 'run_guarded.dart';

class MessageCodeBlockRunner extends ConsumerStatefulWidget {
  const MessageCodeBlockRunner({
    super.key,
    required this.language,
    required this.code,
    this.messageId,
    this.blockIndex = 0,
  });

  final String? language;
  final String code;

  /// The message this block is in, so its Run result is shared. Null leaves
  /// the run ephemeral and per-viewer - see the file doc comment.
  final String? messageId;
  final int blockIndex;

  @override
  ConsumerState<MessageCodeBlockRunner> createState() =>
      _MessageCodeBlockRunnerState();
}

class _MessageCodeBlockRunnerState extends ConsumerState<MessageCodeBlockRunner>
    with GuardedActionState<MessageCodeBlockRunner> {
  bool _running = false;

  /// Only used for the ephemeral (no [messageId]) path; a shared run is read
  /// from [messageExtrasProvider] instead of held here.
  api.RunModuleCommandResult? _ephemeralResult;

  bool get _shared => widget.messageId != null;

  Future<void> _run(api.CodeBlockRunner runner) async {
    setState(() {
      _running = true;
      if (!_shared) _ephemeralResult = null;
    });
    api.RunModuleCommandResult? result;
    final ok = await guard(
      whatFailed: 'run this code block',
      action: () async {
        if (_shared) {
          await ref
              .read(apiProvider)
              .runCodeBlock(
                messageId: widget.messageId!,
                blockIndex: widget.blockIndex,
                moduleId: runner.moduleId,
                command: runner.command,
                input: widget.code,
              );
        } else {
          result = await ref
              .read(apiProvider)
              .runModuleCommand(
                moduleId: runner.moduleId,
                command: runner.command,
                input: widget.code,
              );
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      if (ok && !_shared) _ephemeralResult = result;
    });
  }

  api.CodeRun? _sharedRun() {
    final messageId = widget.messageId;
    if (messageId == null) return null;
    final runs =
        ref.watch(
          messageExtrasProvider.select((m) => m[messageId]?.codeRuns),
        ) ??
        const <api.CodeRun>[];
    for (final run in runs) {
      if (run.blockIndex == widget.blockIndex) return run;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final runners = ref.watch(codeBlockRunnerProvider).valueOrNull ?? const [];
    final runner = matchCodeBlockRunner(runners, widget.language);
    final sharedRun = _shared ? _sharedRun() : null;
    final result = _shared
        ? (sharedRun == null ? null : _asResult(sharedRun))
        : _ephemeralResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCodeBlock(
          language: widget.language,
          lines: lexCodeBlock(widget.code, widget.language),
          action: runner == null
              ? null
              : _RunAction(running: _running, onPressed: () => _run(runner)),
        ),
        if (actionError != null) ...[
          const SizedBox(height: AppSpacing.s4),
          AppErrorState(message: actionError!, onDismiss: clearActionError),
        ],
        if (result != null) ...[
          const SizedBox(height: AppSpacing.s4),
          if (sharedRun != null) const _SharedRunLabel(),
          ModuleCommandOutput(
            result: result,
            moduleId: runner?.moduleId,
            command: runner?.command,
          ),
        ],
      ],
    );
  }

  /// A [CodeRun]'s single `output` is the module's output when it succeeded,
  /// or its error otherwise - the same split [ModuleCommandOutput] renders.
  static api.RunModuleCommandResult _asResult(api.CodeRun run) =>
      api.RunModuleCommandResult(
        ok: run.ok,
        output: run.ok ? run.output : null,
        error: run.ok ? null : run.output,
      );
}

/// A muted line above a shared result, so a viewer who did not run it sees
/// that this output is shared rather than their own private run.
class _SharedRunLabel extends StatelessWidget {
  const _SharedRunLabel();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: Text(
        'Shared result',
        style: AppText.micro.copyWith(
          fontFamily: AppFonts.mono,
          color: tokens.textSecondary,
        ),
      ),
    );
  }
}

/// The header's action slot while idle, or a spinner while a run is in
/// flight - never both, and never a second tap mid-flight since the icon
/// button itself is gone until [running] clears.
class _RunAction extends StatelessWidget {
  const _RunAction({required this.running, required this.onPressed});

  final bool running;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => running
      ? const SizedBox(
          width: AppSizes.icon20,
          height: AppSizes.icon20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : AppIconButton(
          icon: AppIcons.runCode,
          semanticLabel: 'Run code',
          size: AppIconButtonSize.sm,
          onPressed: onPressed,
        );
}
