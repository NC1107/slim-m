// SPDX-License-Identifier: Apache-2.0
/// The two small presentational pieces `canvas_presence_tile.dart` paints
/// over a tile's own content - split out to keep that file, which also
/// carries the tile's gesture handling, under the review budget.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// The corner handle a tile's own resize drag starts from.
class TileResizeGrip extends StatelessWidget {
  const TileResizeGrip({
    super.key,
    required this.onUpdate,
    required this.onEnd,
  });

  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpLeftDownRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: onUpdate,
        onPanEnd: onEnd,
        child: Container(
          width: AppSizes.controlSm,
          height: AppSizes.controlSm,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.surfaceBase.withValues(alpha: 0.85),
            shape: BoxShape.circle,
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Icon(
            AppIcons.tileResize,
            size: AppSizes.icon16,
            color: tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// A tile's own lock, depth and hide buttons, pinned to its top-right
/// corner regardless of whether the tile's content currently paints in
/// front of or behind [CanvasSurface].
class TileControls extends StatelessWidget {
  const TileControls({
    super.key,
    required this.locked,
    required this.sentToBack,
    required this.onToggleLocked,
    required this.onToggleSentToBack,
    required this.onHide,
  });

  final bool locked;
  final bool sentToBack;
  final VoidCallback onToggleLocked;
  final VoidCallback onToggleSentToBack;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: tokens.surfaceBase.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconButton(
            icon: locked ? AppIcons.tileLocked : AppIcons.tileUnlocked,
            semanticLabel: locked
                ? 'Unlock this tile'
                : 'Lock this tile in place',
            tooltip: locked
                ? 'Unlock - drag and resize again'
                : 'Lock in place - a drawing tool reaches through it',
            size: AppIconButtonSize.sm,
            active: locked,
            onPressed: onToggleLocked,
          ),
          // The object menu's own "Bring to front"/"Send to back", reached here since a tile absorbs its own right-click - see `canvas_presence_tile.dart`'s own library doc.
          AppIconButton(
            icon: sentToBack ? AppIcons.sendToBack : AppIcons.bringToFront,
            semanticLabel: sentToBack
                ? 'Bring this tile to the front'
                : 'Send this tile to the back',
            tooltip: sentToBack
                ? 'Bring to front - back above the ink'
                : 'Send to back - draw over it',
            size: AppIconButtonSize.sm,
            active: sentToBack,
            onPressed: onToggleSentToBack,
          ),
          AppIconButton(
            icon: AppIcons.tileHide,
            semanticLabel: 'Hide this tile on your canvas',
            tooltip: 'Hide on your canvas',
            size: AppIconButtonSize.sm,
            onPressed: onHide,
          ),
        ],
      ),
    );
  }
}
