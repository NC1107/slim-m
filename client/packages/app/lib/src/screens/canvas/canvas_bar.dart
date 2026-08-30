// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The canvas pane's own minimal identity strip.
///
/// This used to be the canvas's entire toolbar - five tools, undo, the
/// overflow menu and close, all pinned across the top with the interactive
/// controls pushed to the far corner. The owner reported the flow did not
/// work: the controls sat far from the hand doing the drawing, and opening
/// the canvas during a call made the call's own controls disappear outright.
/// Both are fixed by moving every interactive control into `CanvasCallDock`,
/// a floating card near the bottom of the pane - see that file's own doc for
/// the full reasoning. What is left here is purely identity: an icon, a
/// label, and the screen-reader landmark `canvas_pane_semantics_test.dart`
/// already depends on. Nothing here is a button.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

class CanvasBar extends StatelessWidget {
  const CanvasBar({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.paneGutter),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AppIcons.canvas,
            size: AppSizes.icon16,
            color: tokens.textSecondary,
          ),
          const SizedBox(width: AppSpacing.s8),
          Semantics(
            container: true,
            header: true,
            child: Text(
              'Canvas',
              style: AppText.body.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.medium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
