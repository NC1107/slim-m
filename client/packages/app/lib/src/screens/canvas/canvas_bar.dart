// SPDX-License-Identifier: Apache-2.0
/// The canvas pane's own header.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'canvas_overflow_menu.dart';

/// The canvas's own bar. It carries the close affordance because the pane
/// replaces the conversation, header and all, at every width.
class CanvasBar extends StatelessWidget {
  const CanvasBar({
    super.key,
    required this.channelId,
    required this.onClose,
    required this.tool,
    required this.onToolChanged,
    required this.canUndo,
    required this.onUndo,
    required this.canManage,
    required this.objectCount,
    required this.onClear,
    required this.onPasteImage,
    required this.selection,
    required this.onBringToFront,
    required this.onSendToBack,
    required this.activityLogOpen,
    required this.onToggleActivityLog,
  });

  final String channelId;
  final VoidCallback onClose;

  /// Which tool a tap or drag on the surface draws with. Three tools is
  /// still a toggle row, not a dock: nothing here needs a picker, and a
  /// floating panel would only add a container around the same three
  /// buttons this bar already has room for.
  final CanvasTool tool;
  final ValueChanged<CanvasTool> onToolChanged;

  final bool canUndo;
  final VoidCallback onUndo;

  /// Whether the signed-in member holds MANAGE_CANVAS, deployment-wide. A
  /// control that can appear and 403 in a channel an overwrite denies it in,
  /// the same compromise `manage_channel_sheet.dart` already makes.
  final bool canManage;

  /// The live count [CanvasOverflowMenu]'s confirm names, so it never quotes
  /// a number from before the pane's own first fetch.
  final ValueListenable<int> objectCount;

  /// Clears the canvas as of whatever the pane's own cursor is when this
  /// fires, not a value captured at build time. A failure is reported the
  /// same way any other op failure is, through the pane's own error state.
  final Future<void> Function() onClear;

  /// Reads the clipboard and, if it holds an image, places it. Lives in the
  /// overflow menu, reachable regardless of MANAGE_CANVAS, since placing an
  /// image needs only the same USE_CANVAS bit drawing already does.
  final VoidCallback onPasteImage;

  /// The one object currently selected for a resize or reorder, or null -
  /// forwarded to [CanvasOverflowMenu] so its own doc on why "Bring to
  /// front"/"Send to back" only appear then applies here too.
  final ValueListenable<String?> selection;
  final ValueChanged<String> onBringToFront;
  final ValueChanged<String> onSendToBack;

  /// The accessibility fallback's own open state and toggle, threaded
  /// straight through to the overflow menu - see that file for why it lives
  /// there rather than as a dedicated bar icon.
  final bool activityLogOpen;
  final VoidCallback onToggleActivityLog;

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
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.medium,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          AppIconButton(
            icon: AppIcons.pen,
            semanticLabel: 'Pen',
            active: tool == CanvasTool.pen,
            onPressed: () => onToolChanged(CanvasTool.pen),
          ),
          const SizedBox(width: AppSpacing.s4),
          AppIconButton(
            icon: AppIcons.eraser,
            semanticLabel: 'Eraser',
            active: tool == CanvasTool.eraser,
            onPressed: () => onToolChanged(CanvasTool.eraser),
          ),
          const SizedBox(width: AppSpacing.s4),
          AppIconButton(
            icon: AppIcons.select,
            semanticLabel: 'Move',
            active: tool == CanvasTool.select,
            onPressed: () => onToolChanged(CanvasTool.select),
          ),
          const SizedBox(width: AppSpacing.s8),
          AppIconButton(
            icon: AppIcons.undo,
            semanticLabel: 'Undo',
            onPressed: canUndo ? onUndo : null,
          ),
          const SizedBox(width: AppSpacing.s4),
          CanvasOverflowMenu(
            onPasteImage: onPasteImage,
            canManage: canManage,
            objectCount: objectCount,
            onClear: onClear,
            selection: selection,
            onBringToFront: onBringToFront,
            onSendToBack: onSendToBack,
            activityLogOpen: activityLogOpen,
            onToggleActivityLog: onToggleActivityLog,
          ),
          const SizedBox(width: AppSpacing.s4),
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
