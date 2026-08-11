// SPDX-License-Identifier: Apache-2.0
/// The canvas's own row of interactive controls: the five tools, undo, the
/// overflow menu and close - everything that used to live on `CanvasBar`'s
/// top strip, extracted unchanged in mechanism so it can sit inside
/// `CanvasCallDock` instead.
///
/// The scroll-and-fade behaviour for the tool cluster is the identical code
/// that already shipped and was already proven correct by
/// `canvas_bar_touch_reach_test.dart`: at phone width five tools plus undo,
/// overflow and close do not fit one row, and folding a tool into a menu was
/// rejected once already ("keeps every tool a same-level, one-tap button" -
/// decision 0004). So it scrolls, with a fade on whichever edge still has
/// something to reveal, exactly as before - only its container changed, not
/// its logic, which is why this file is a relocation rather than a rewrite.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'canvas_overflow_menu.dart';
import 'canvas_shape_icons.dart';

/// Read by tests to find the tool strip's edge fades without matching on any
/// decorated container that merely happens to carry a gradient.
const canvasToolsLeadingFadeKey = Key('canvas-tools-fade-leading');
const canvasToolsTrailingFadeKey = Key('canvas-tools-fade-trailing');

/// One camera or screen-share tile this viewer has hidden on their own
/// canvas - the overflow menu's own recovery list names it by [label]
/// rather than the raw `'camera:<identity>'` key, and hands [key] straight
/// back to `CanvasPresenceTileOverrides.setHidden` on tap.
class CanvasHiddenTile {
  const CanvasHiddenTile({required this.key, required this.label});

  final String key;
  final String label;
}

class CanvasToolsRow extends StatefulWidget {
  const CanvasToolsRow({
    super.key,
    required this.tool,
    required this.onToolChanged,
    required this.canDraw,
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
    required this.onClose,
    required this.hasSelfBubble,
    required this.selfBubbleHidden,
    required this.onToggleSelfBubbleHidden,
    required this.hiddenTiles,
    required this.onShowTile,
    this.showTools = true,
  });

  /// Which tool a tap or drag on the surface draws with. Pen, note and shape
  /// are decision 0004's own three tool-dock tools, each dropping a new
  /// object where a pointer taps; eraser and select act on objects already
  /// there rather than placing a new one.
  final CanvasTool tool;
  final ValueChanged<CanvasTool> onToolChanged;

  /// False while the pane's own error banner is up - an active refusal
  /// (forbidden, or a timeout freeze) that would make placing a new object
  /// fail the identical way again. Disarms pen, note and shape (and the
  /// overflow's "Paste image"), the exact tools the empty-canvas CTA this
  /// screen-review finding names invites - a still-selectable pen tool
  /// underneath a banner reading "the canvas is not available" or "you
  /// cannot draw right now" invites the same failure the banner already
  /// described. Eraser and select are left alone: the finding is about
  /// placing specifically, and disabling an edit tool needs knowing which
  /// error is showing (a broad view denial reaches everything; a place-only
  /// timeout freeze does not), which this row is not told.
  final bool canDraw;

  /// The primitive the next tap with the shape tool places. Read only by
  /// [CanvasOverflowMenu]'s own picker, which appears while [tool] is
  /// [CanvasTool.shape]; this row has no picker of its own.
  final CanvasShapeKind shapeKind;
  final ValueChanged<CanvasShapeKind> onShapeKindChanged;

  final bool canUndo;
  final VoidCallback onUndo;

  /// Whether the signed-in member holds MANAGE_CANVAS, deployment-wide.
  final bool canManage;

  /// The live count [CanvasOverflowMenu]'s confirm names.
  final ValueListenable<int> objectCount;

  final Future<void> Function() onClear;
  final VoidCallback onPasteImage;
  final VoidCallback onRecenter;

  /// The one object currently selected for a resize or reorder, or null.
  final ValueListenable<String?> selection;
  final ValueChanged<String> onBringToFront;
  final ValueChanged<String> onSendToBack;
  final ValueChanged<String> onDeleteSelected;

  final bool activityLogOpen;
  final VoidCallback onToggleActivityLog;

  /// Closes the canvas outright, returning to whatever this channel showed
  /// before - the dock's own answer to `CanvasBar`'s old "Close canvas".
  final VoidCallback onClose;

  /// Whether the caller is on this channel's call at all - the overflow's
  /// own "Hide/Show my camera bubble" item only appears then, the same "no
  /// button that would do nothing" rule [activityLogOpen]'s sibling item is
  /// exempt from because the log itself always exists.
  final bool hasSelfBubble;
  final bool selfBubbleHidden;
  final VoidCallback onToggleSelfBubbleHidden;

  /// Every remote tile hidden on this viewer's own canvas right now, and
  /// the recovery action for each - the overflow's own "N hidden" section.
  final List<CanvasHiddenTile> hiddenTiles;
  final ValueChanged<String> onShowTile;

  /// False while the activity panel has replaced the drawing surface: there
  /// is nothing to draw on, so the five placement/edit tools fold away and
  /// only undo, the overflow (which still offers "Hide activity log") and
  /// close remain.
  final bool showTools;

  @override
  State<CanvasToolsRow> createState() => _CanvasToolsRowState();
}

class _CanvasToolsRowState extends State<CanvasToolsRow> {
  final _toolsScroll = ScrollController();
  bool _fadeLeading = false;
  bool _fadeTrailing = false;

  @override
  void dispose() {
    _toolsScroll.dispose();
    super.dispose();
  }

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

  Widget _edgeFade(AppTokens tokens, {required bool leading}) => IgnorePointer(
    child: Container(
      key: leading ? canvasToolsLeadingFadeKey : canvasToolsTrailingFadeKey,
      width: AppSpacing.s24,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: leading ? Alignment.centerLeft : Alignment.centerRight,
          end: leading ? Alignment.centerRight : Alignment.centerLeft,
          colors: [tokens.surfaceRaised, tokens.surfaceRaised.withAlpha(0)],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Row(
      children: [
        if (widget.showTools)
          Expanded(child: _toolStrip(tokens))
        else
          const Spacer(),
        const SizedBox(width: AppSpacing.s8),
        AppIconButton(
          icon: AppIcons.undo,
          semanticLabel: 'Undo',
          tooltip: widget.canUndo ? 'Undo' : 'Nothing to undo yet',
          onPressed: widget.canUndo ? widget.onUndo : null,
        ),
        const SizedBox(width: AppSpacing.s4),
        CanvasOverflowMenu(
          onPasteImage: widget.onPasteImage,
          canDraw: widget.canDraw,
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
          hasSelfBubble: widget.hasSelfBubble,
          selfBubbleHidden: widget.selfBubbleHidden,
          onToggleSelfBubbleHidden: widget.onToggleSelfBubbleHidden,
          hiddenTiles: widget.hiddenTiles,
          onShowTile: widget.onShowTile,
        ),
        const SizedBox(width: AppSpacing.s4),
        AppIconButton(
          icon: AppIcons.dismiss,
          semanticLabel: 'Close canvas',
          tooltip: 'Close canvas',
          onPressed: widget.onClose,
        ),
      ],
    );
  }

  Widget _toolStrip(AppTokens tokens) => Stack(
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
                  tooltip: widget.canDraw ? 'Pen' : "Can't draw right now",
                  active: widget.tool == CanvasTool.pen,
                  onPressed: widget.canDraw
                      ? () => widget.onToolChanged(CanvasTool.pen)
                      : null,
                ),
                const SizedBox(width: AppSpacing.s4),
                AppIconButton(
                  icon: AppIcons.note,
                  semanticLabel: 'Note',
                  tooltip: widget.canDraw ? 'Note' : "Can't draw right now",
                  active: widget.tool == CanvasTool.note,
                  onPressed: widget.canDraw
                      ? () => widget.onToolChanged(CanvasTool.note)
                      : null,
                ),
                const SizedBox(width: AppSpacing.s4),
                AppIconButton(
                  // The armed kind's own glyph, not a generic one - state must be visible, not just remembered.
                  icon: canvasShapeKindIcon(widget.shapeKind),
                  semanticLabel: 'Shape',
                  tooltip: widget.canDraw
                      ? 'Shape · ${canvasShapeKindLabel(widget.shapeKind)} armed, '
                            'pick another from "More canvas actions"'
                      : "Can't draw right now",
                  active: widget.tool == CanvasTool.shape,
                  onPressed: widget.canDraw
                      ? () => widget.onToolChanged(CanvasTool.shape)
                      : null,
                ),
                const SizedBox(width: AppSpacing.s4),
                AppIconButton(
                  icon: AppIcons.eraser,
                  semanticLabel: 'Eraser',
                  tooltip:
                      'Eraser · pen ink only, select then Delete for a '
                      'note, shape or image',
                  active: widget.tool == CanvasTool.eraser,
                  onPressed: () => widget.onToolChanged(CanvasTool.eraser),
                ),
                const SizedBox(width: AppSpacing.s4),
                AppIconButton(
                  icon: AppIcons.select,
                  semanticLabel: 'Move',
                  tooltip:
                      'Move an object, or select a stroke to reorder it '
                      '· hold Shift while resizing to free the aspect '
                      'ratio',
                  active: widget.tool == CanvasTool.select,
                  onPressed: () => widget.onToolChanged(CanvasTool.select),
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
  );
}
