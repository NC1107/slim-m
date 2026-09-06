// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// One module command's result, notebook-style: its own bordered panel,
/// monospace, tinted for an error rather than only labelled. Shared by
/// [MessageCodeBlockRunner] and the Dock's command panel so a module's
/// output reads the same wherever it is triggered from.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

class ModuleCommandOutput extends StatelessWidget {
  const ModuleCommandOutput({super.key, required this.result});

  final api.RunModuleCommandResult result;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final isError = !result.ok;
    final text = (isError ? result.error : result.output) ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border.all(
          color: isError ? tokens.dangerBorder : tokens.borderSubtle,
        ),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isError ? 'Error' : 'Output',
            style: AppText.micro.copyWith(
              fontFamily: AppFonts.mono,
              color: isError ? tokens.dangerText : tokens.textSecondary,
            ),
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
