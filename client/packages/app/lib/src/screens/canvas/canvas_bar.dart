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
///
/// The label used to say only "Canvas", dropped as a side effect of that
/// same pass rather than a considered choice: with several voice channels
/// each carrying their own canvas, alt-tabbing back gave no way to tell
/// which one this was, unlike the voice call header beside it. [channelId]
/// resolves the channel's own name through `channelByIdProvider`, the same
/// row `CallChannelName` reads, so a DM's canvas names its peer the
/// identical way `_DmCallBar` already does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../../providers/channel_by_id_provider.dart';

class CanvasBar extends ConsumerWidget {
  const CanvasBar({super.key, required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final name = ref.watch(channelByIdProvider(channelId)).valueOrNull?.name;
    final label = name == null || name.isEmpty ? 'Canvas' : 'Canvas · $name';
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.paneGutter),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(
            AppIcons.canvas,
            size: AppSizes.icon16,
            color: tokens.textSecondary,
          ),
          const SizedBox(width: AppSpacing.s8),
          Flexible(
            child: Semantics(
              container: true,
              header: true,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: AppWeights.medium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
