// SPDX-License-Identifier: Apache-2.0
/// The canvas pane's own header.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'canvas_overflow_menu.dart';
import 'canvas_shape_icons.dart';

/// Read by `canvas_bar_test.dart` to find the tool strip's edge fades
/// without matching on any decorated container that merely happens to
/// carry a gradient.
const canvasBarLeadingFadeKey = Key('canvas-bar-tools-fade-leading');
const canvasBarTrailingFadeKey = Key('canvas-bar-tools-fade-trailing');

/// The canvas's own bar. It carries the close affordance because the pane
/// replaces the conversation, header and all, at every width.
class CanvasBar extends StatefulWidget {
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
    required this.onRecenter,
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

  /// Jumps the camera back to the world origin, gated on nothing - see
  /// `CanvasOverflowMenu`'s own doc for why.
  final VoidCallback onRecenter;

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
  State<CanvasBar> createState() => _CanvasBarState();
}

class _CanvasBarState extends State<CanvasBar> {
  final _toolsScroll = ScrollController();

  /// Whether the tool strip has content scrolled past on that side right
  /// now - the only two things that ever change these, a drag or the strip
  /// itself gaining or losing overflow (a resize), both reach here through
  /// [_onToolsScrollMetrics], never through `widget` fields, since neither
  /// is a property of what this bar was built with.
  bool _fadeLeading = false;
  bool _fadeTrailing = false;

  @override
  void dispose() {
    _toolsScroll.dispose();
    super.dispose();
  }

  /// A tool clipped off the visible strip has no other cue it exists - see
  /// this file's own library doc. Fires on a real drag and, since
  /// [ScrollMetricsNotification] carries no offset change of its own, on a
  /// resize that starts or stops overflowing with the scroll position
  /// untouched, which a plain [ScrollController] listener would miss.
  bool _onToolsScrollMetrics(ScrollMetricsNotification notification) =>
      _applyToolsScrollMetrics(notification.metrics);

  bool _onToolsScroll(ScrollNotification notification) =>
      _applyToolsScrollMetrics(notification.metrics);

  bool _applyToolsScrollMetrics(ScrollMetrics metrics) {
    final leading = metrics.pixels > metrics.minScrollExtent;
    final trailing = metrics.pixels < metrics.maxScrollExtent;
    if (leading != _fadeLeading || trailing != _fadeTrailing) {
      setState(() {
        _fadeLeading = leading;
        _fadeTrailing = trailing;
      });
    }
    return false;
  }

  /// A hairline-thin gradient the same colour as what the bar already
  /// paints over, so a tool cut off by it still reads as "more here" rather
  /// than as a hard edge - the same reasoning `AppTokens.stripe` and
  /// `AppShadows.float` already document for a token existing to name one
  /// specific visual job.
  Widget _edgeFade(AppTokens tokens, {required bool leading}) => IgnorePointer(
    child: Container(
      key: leading ? canvasBarLeadingFadeKey : canvasBarTrailingFadeKey,
      width: AppSpacing.s24,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: leading ? Alignment.centerLeft : Alignment.centerRight,
          end: leading ? Alignment.centerRight : Alignment.centerLeft,
          colors: [tokens.surfaceBase, tokens.surfaceBase.withAlpha(0)],
        ),
      ),
    ),
  );

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
          // Five tool buttons at a phone's touch-target size do not fit a phone-width bar; scrolling here, rather than folding any of them into a menu, keeps every tool a same-level, one-tap button. The edge fades are what say so - a bare clipped icon reads as a broken layout, not an invitation to swipe.
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                NotificationListener<ScrollMetricsNotification>(
                  onNotification: _onToolsScrollMetrics,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onToolsScroll,
                    child: SingleChildScrollView(
                      controller: _toolsScroll,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIconButton(
                            icon: AppIcons.pen,
                            semanticLabel: 'Pen',
                            tooltip: 'Pen',
                            active: widget.tool == CanvasTool.pen,
                            onPressed: () =>
                                widget.onToolChanged(CanvasTool.pen),
                          ),
                          const SizedBox(width: AppSpacing.s4),
                          AppIconButton(
                            icon: AppIcons.note,
                            semanticLabel: 'Note',
                            tooltip: 'Note',
                            active: widget.tool == CanvasTool.note,
                            onPressed: () =>
                                widget.onToolChanged(CanvasTool.note),
                          ),
                          const SizedBox(width: AppSpacing.s4),
                          AppIconButton(
                            // The armed kind's own glyph, not a generic one - a control whose look never changes with its state is one you have to remember rather than read.
                            icon: canvasShapeKindIcon(widget.shapeKind),
                            semanticLabel: 'Shape',
                            // The tooltip is where a screen reader learns the icon's own state, since it carries as a semantics hint and the icon change is visual-only.
                            tooltip:
                                'Shape · ${canvasShapeKindLabel(widget.shapeKind)} armed, '
                                'pick another from "More canvas actions"',
                            active: widget.tool == CanvasTool.shape,
                            onPressed: () =>
                                widget.onToolChanged(CanvasTool.shape),
                          ),
                          const SizedBox(width: AppSpacing.s4),
                          AppIconButton(
                            icon: AppIcons.eraser,
                            semanticLabel: 'Eraser',
                            // Erases pen ink only - it hit-tests a stroke's own path, which a note, shape or image has none of; nothing else says so.
                            tooltip:
                                'Eraser · pen ink only, select then Delete for a '
                                'note, shape or image',
                            active: widget.tool == CanvasTool.eraser,
                            onPressed: () =>
                                widget.onToolChanged(CanvasTool.eraser),
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
                            active: widget.tool == CanvasTool.select,
                            onPressed: () =>
                                widget.onToolChanged(CanvasTool.select),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_fadeLeading)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _edgeFade(tokens, leading: true),
                  ),
                if (_fadeTrailing)
                  Align(
                    alignment: Alignment.centerRight,
                    child: _edgeFade(tokens, leading: false),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          AppIconButton(
            icon: AppIcons.undo,
            semanticLabel: 'Undo',
            // Disabled must say why, not only look greyed out - the same "state why unavailable" rule the design language sets for every other disabled control here.
            tooltip: widget.canUndo ? 'Undo' : 'Nothing to undo yet',
            onPressed: widget.canUndo ? widget.onUndo : null,
          ),
          const SizedBox(width: AppSpacing.s4),
          CanvasOverflowMenu(
            onPasteImage: widget.onPasteImage,
            onRecenter: widget.onRecenter,
            canManage: widget.canManage,
            objectCount: widget.objectCount,
            onClear: widget.onClear,
            selection: widget.selection,
            onBringToFront: widget.onBringToFront,
            onSendToBack: widget.onSendToBack,
            onDeleteSelected: widget.onDeleteSelected,
            activityLogOpen: widget.activityLogOpen,
            onToggleActivityLog: widget.onToggleActivityLog,
            tool: widget.tool,
            shapeKind: widget.shapeKind,
            onShapeKindChanged: widget.onShapeKindChanged,
          ),
          const SizedBox(width: AppSpacing.s4),
          AppIconButton(
            icon: AppIcons.dismiss,
            semanticLabel: 'Close canvas',
            tooltip: 'Close canvas',
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }
}
