// SPDX-License-Identifier: Apache-2.0
/// The canvas pane's widget tree: the bar, the error and truncation
/// banners, and the drawing surface.
///
/// Split out of `canvas_pane.dart`, which was already past the review
/// budget before this slice added the eraser, undo and clear controls to
/// it. `_CanvasPaneState` owns every callback and every piece of state
/// this only renders; nothing here reaches Riverpod.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'canvas_bar.dart';

class CanvasPaneBody extends StatelessWidget {
  const CanvasPaneBody({
    super.key,
    required this.channelId,
    required this.onClose,
    required this.tool,
    required this.onToolChanged,
    required this.canUndo,
    required this.onUndo,
    required this.canManage,
    required this.document,
    required this.onClear,
    required this.onPasteImage,
    required this.error,
    required this.onDismissError,
    required this.truncated,
    required this.loading,
    required this.onStroke,
    required this.onErase,
    required this.onEraseEnd,
    required this.onSelectStart,
    required this.onSelectDrag,
    required this.onSelectEnd,
    this.cursors,
    this.cursorColors = const [],
    this.onPointerMoved,
  });

  final String channelId;
  final VoidCallback onClose;
  final CanvasTool tool;
  final ValueChanged<CanvasTool> onToolChanged;
  final bool canUndo;
  final VoidCallback onUndo;
  final bool canManage;
  final CanvasDocument document;
  final Future<void> Function() onClear;

  /// The toolbar's "Paste image" action, always available - the manual
  /// fallback that works on every platform, the same shape the composer's
  /// own "+" sheet row already is.
  final VoidCallback onPasteImage;
  final String? error;
  final VoidCallback onDismissError;
  final bool truncated;
  final bool loading;
  final StrokeCommitted onStroke;
  final ValueChanged<Offset> onErase;
  final VoidCallback onEraseEnd;
  final ValueChanged<Offset> onSelectStart;
  final ValueChanged<Offset> onSelectDrag;
  final VoidCallback onSelectEnd;

  /// Other participants' live pointers, and the palette their colours are
  /// drawn from. Null renders no cursor layer, the same "cheap to omit"
  /// shape [CanvasSurface] itself already offers.
  final CanvasCursors? cursors;
  final List<Color> cursorColors;
  final PointerMoved? onPointerMoved;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // No AppBar sits above CanvasBar, so this pane insets itself for top/bottom; left stays unconsumed because a rail, not this pane, ever occupies the true left edge.
    return Container(
      color: tokens.surfaceBase,
      child: SafeArea(
        left: false,
        child: Column(
          children: [
            CanvasBar(
              channelId: channelId,
              onClose: onClose,
              tool: tool,
              onToolChanged: onToolChanged,
              canUndo: canUndo,
              onUndo: onUndo,
              canManage: canManage,
              objectCount: document.objectCount,
              onClear: onClear,
              onPasteImage: onPasteImage,
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.s12),
                child: AppErrorState(
                  message: error!,
                  onDismiss: onDismissError,
                ),
              ),
            if (truncated)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s12,
                  0,
                  AppSpacing.s12,
                  AppSpacing.s12,
                ),
                child: const AppCallout(
                  child: Text(
                    'Some ink in this region is not shown. Zoom in to see it.',
                  ),
                ),
              ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: document.objectCount,
                builder: (context, count, child) => Semantics(
                  container: true,
                  label: loading
                      ? 'Canvas, loading'
                      : 'Canvas, $count objects drawn',
                  child: child,
                ),
                child: CanvasSurface(
                  document: document,
                  ink: AppCanvasColors.annotation,
                  gridLine: tokens.borderSubtle,
                  onStroke: onStroke,
                  tool: tool,
                  onErase: onErase,
                  onEraseEnd: onEraseEnd,
                  onSelectStart: onSelectStart,
                  onSelectDrag: onSelectDrag,
                  onSelectEnd: onSelectEnd,
                  cursors: cursors,
                  cursorColors: cursorColors,
                  onPointerMoved: onPointerMoved,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
