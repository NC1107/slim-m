// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A fenced code block plus its optional "Run" affordance and, once run, its
/// output rendered inline below - notebook-style, monospace, clearly
/// delimited from the code above it.
///
/// The affordance itself is driven entirely by [codeBlockRunnerProvider] and
/// [matchCodeBlockRunner]: this file has no notion of what running code
/// means, only of "match this block's own language tag to a discovered
/// runner, then POST its text to whatever (module_id, command) that runner
/// named" - see docs/decisions/0021-modules-and-the-dock.md's
/// module-agnostic principle. No Run affordance shows at all when no runner
/// matches this block's language.
///
/// The output is ephemeral and per-viewer: it lives only in this widget's own
/// state, is never persisted or broadcast, and a second run replaces it
/// rather than appending to it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/code_block_runner.dart';
import '../providers/providers.dart';
import 'message_code_lexer.dart';
import 'module_command_output.dart';
import 'run_guarded.dart';

class MessageCodeBlockRunner extends ConsumerStatefulWidget {
  const MessageCodeBlockRunner({
    super.key,
    required this.language,
    required this.code,
  });

  final String? language;
  final String code;

  @override
  ConsumerState<MessageCodeBlockRunner> createState() =>
      _MessageCodeBlockRunnerState();
}

class _MessageCodeBlockRunnerState extends ConsumerState<MessageCodeBlockRunner>
    with GuardedActionState<MessageCodeBlockRunner> {
  bool _running = false;
  api.RunModuleCommandResult? _result;

  Future<void> _run(api.CodeBlockRunner runner) async {
    setState(() {
      _running = true;
      _result = null;
    });
    api.RunModuleCommandResult? result;
    final ok = await guard(
      whatFailed: 'run this code block',
      action: () async {
        result = await ref
            .read(apiProvider)
            .runModuleCommand(
              moduleId: runner.moduleId,
              command: runner.command,
              input: widget.code,
            );
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      if (ok) _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final runners = ref.watch(codeBlockRunnerProvider).valueOrNull ?? const [];
    final runner = matchCodeBlockRunner(runners, widget.language);
    final result = _result;
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
          ModuleCommandOutput(result: result),
        ],
      ],
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
