// SPDX-License-Identifier: Apache-2.0
/// The canvas pane's own header.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// The canvas's own bar. It carries the close affordance because the pane
/// replaces the conversation, header and all, at every width.
class CanvasBar extends StatelessWidget {
  const CanvasBar({super.key, required this.channelId, required this.onClose});

  final String channelId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.paneGutter),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(
            AppIcons.canvas,
            size: AppSizes.icon16,
            color: tokens.textSecondary,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Text(
              'Canvas',
              style: AppText.body.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.medium,
              ),
            ),
          ),
          AppIconButton(
            icon: AppIcons.dismiss,
            semanticLabel: 'Close canvas',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
