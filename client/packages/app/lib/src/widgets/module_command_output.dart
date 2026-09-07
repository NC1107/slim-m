// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// One module command's result. When the module returned a scene (see
/// `module_scene.dart`), this paints it interactively; otherwise it shows the
/// output notebook-style: its own bordered panel, monospace, tinted for an
/// error rather than only labelled. Shared by [MessageCodeBlockRunner] and the
/// Dock's command panel so a module's output reads the same wherever it is
/// triggered from.
///
/// [moduleId] and [command] are what a scene needs to run its own follow-up
/// actions (step, tap, ...) back against the same module; without them a scene
/// still renders, just as a static first frame with no controls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import 'module_scene.dart';
import 'module_scene_view.dart';

class ModuleCommandOutput extends ConsumerWidget {
  const ModuleCommandOutput({
    super.key,
    required this.result,
    this.moduleId,
    this.command,
  });

  final api.RunModuleCommandResult result;
  final String? moduleId;
  final String? command;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final output = result.output;
    final moduleId = this.moduleId;
    final command = this.command;
    if (result.ok && output != null && moduleId != null && command != null) {
      final scene = parseModuleScene(output);
      if (scene != null) {
        return ModuleSceneView(
          initial: scene,
          runCommand: (input) => ref
              .read(apiProvider)
              .runModuleCommand(
                moduleId: moduleId,
                command: command,
                input: input,
              ),
        );
      }
    }

    final isError = !result.ok;
    final text = (isError ? result.error : result.output) ?? '';
    // Recessed (sunken), not raised like the code block above it, so the result reads as the answer that came out of the code, not more code.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: isError ? tokens.surfaceRaised : tokens.surfaceSunken,
        border: Border.all(
          color: isError ? tokens.dangerBorder : tokens.borderSubtle,
        ),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                AppIcons.forward,
                size: AppSizes.icon16,
                color: isError ? tokens.dangerText : tokens.textSecondary,
              ),
              const SizedBox(width: AppSpacing.s4),
              Text(
                isError ? 'Error' : 'Result',
                style: AppText.micro.copyWith(
                  fontFamily: AppFonts.mono,
                  color: isError ? tokens.dangerText : tokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          SelectableText(
            text,
            // 13/1.6 match AppCodeBlock's own fenced-block body exactly, so output reads as a continuation of the code above it, not a mismatched font.
            style: TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 13,
              height: 1.6,
              color: isError ? tokens.dangerText : tokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
