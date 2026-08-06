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
    required this.onDeleteSelected,
    required this.activityLogOpen,
    required this.onToggleActivityLog,
    required this.shapeKind,
    required this.onShapeKindChanged,
  });

  final String channelId;
  final VoidCallback onClose;

  /// Which tool a tap or drag on the surface draws with. Pen, note and
  /// shape are decision 0004's own three tool-dock tools, each dropping a
  /// new object where a pointer taps; eraser and select act on objects
  /// already there rather than placing a new one.
  final CanvasTool tool;
  final ValueChanged<CanvasTool> onToolChanged;

  /// The primitive the next tap with the shape tool places. Read only by
  /// [CanvasOverflowMenu]'s own picker, which appears while [tool] is
  /// [CanvasTool.shape]; this bar has no picker of its own.
  final CanvasShapeKind shapeKind;
  final ValueChanged<CanvasShapeKind> onShapeKindChanged;

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

  /// Removes the current selection - see [CanvasOverflowMenu]'s own doc for
  /// why this needs no confirm dialog, unlike clearing the whole canvas.
  final ValueChanged<String> onDeleteSelected;

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
          // A fixed label, not Expanded: "Canvas" is a constant string, never a channel name, so it never needs to shrink - the tool cluster is what needs the room a phone-width bar is short on.
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
          const SizedBox(width: AppSpacing.s8),
          // Five tool buttons at a phone's touch-target size do not fit a phone-width bar; scrolling here, rather than folding any of them into a menu, keeps every tool a same-level, one-tap button.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIconButton(
                    icon: AppIcons.pen,
                    semanticLabel: 'Pen',
                    tooltip: 'Pen',
                    active: tool == CanvasTool.pen,
                    onPressed: () => onToolChanged(CanvasTool.pen),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  AppIconButton(
                    icon: AppIcons.note,
                    semanticLabel: 'Note',
                    tooltip: 'Note',
                    active: tool == CanvasTool.note,
                    onPressed: () => onToolChanged(CanvasTool.note),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  AppIconButton(
                    icon: AppIcons.shape,
                    semanticLabel: 'Shape',
                    // Which shape is picked from "More canvas actions" while this tool is active; nothing on the bar itself names it.
                    tooltip:
                        'Shape · pick which one from "More canvas actions"',
                    active: tool == CanvasTool.shape,
                    onPressed: () => onToolChanged(CanvasTool.shape),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  AppIconButton(
                    icon: AppIcons.eraser,
                    semanticLabel: 'Eraser',
                    // Erases pen ink only - it hit-tests a stroke's own path, which a note, shape or image has none of; nothing else says so.
                    tooltip:
                        'Eraser · pen ink only, select then Delete for a '
                        'note, shape or image',
                    active: tool == CanvasTool.eraser,
                    onPressed: () => onToolChanged(CanvasTool.eraser),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  AppIconButton(
                    icon: AppIcons.select,
                    semanticLabel: 'Move',
                    // Answers three things nothing else on screen says: dragging only picks up a box object (image, note, shape), a stroke can only be reordered, and Shift frees the aspect ratio while resizing.
                    tooltip:
                        'Move an object, or select a stroke to reorder it '
                        '· hold Shift while resizing to free the aspect '
                        'ratio',
                    active: tool == CanvasTool.select,
                    onPressed: () => onToolChanged(CanvasTool.select),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          AppIconButton(
            icon: AppIcons.undo,
            semanticLabel: 'Undo',
            // Disabled must say why, not only look greyed out - the same "state why unavailable" rule the design language sets for every other disabled control here.
            tooltip: canUndo ? 'Undo' : 'Nothing to undo yet',
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
            onDeleteSelected: onDeleteSelected,
            activityLogOpen: activityLogOpen,
            onToggleActivityLog: onToggleActivityLog,
            tool: tool,
            shapeKind: shapeKind,
            onShapeKindChanged: onShapeKindChanged,
          ),
          const SizedBox(width: AppSpacing.s4),
          AppIconButton(
            icon: AppIcons.dismiss,
            semanticLabel: 'Close canvas',
            tooltip: 'Close canvas',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
