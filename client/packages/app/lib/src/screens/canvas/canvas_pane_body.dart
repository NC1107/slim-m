// SPDX-License-Identifier: Apache-2.0
/// The canvas pane's widget tree: the bar, the error and truncation
/// banners, the drawing surface, and the text activity log a screen reader
/// can browse in place of it.
///
/// Split out of `canvas_pane.dart`, which was already past the review
/// budget before this slice added the eraser, undo and clear controls to
/// it. `_CanvasPaneState` owns every callback and every piece of state that
/// has to survive the pane's own lifetime; whether the activity panel is
/// open right now is pure presentation, so it is this widget's own local
/// state instead of one more field threaded through an already-large parent.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'canvas_activity_log.dart';
import 'canvas_activity_panel.dart';
import 'canvas_bar.dart';
import 'canvas_presence_layer.dart';

class CanvasPaneBody extends StatefulWidget {
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
    required this.onBringToFront,
    required this.onSendToBack,
    required this.activityLog,
    this.cursors,
    this.cursorColors = const [],
    this.onPointerMoved,
    this.callParticipants = const [],
    required this.cameraViewFor,
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
  final ValueChanged<String> onBringToFront;
  final ValueChanged<String> onSendToBack;

  /// The accessibility fallback: who placed, moved, removed, cleared or
  /// restored what, filtered for blocking exactly as a remote cursor
  /// already is. Owned by `_CanvasPaneState` and outlives a panel toggle,
  /// so the history survives closing and reopening the panel within one
  /// session.
  final CanvasActivityLog activityLog;

  /// Other participants' live pointers, and the palette their colours are
  /// drawn from. Null renders no cursor layer, the same "cheap to omit"
  /// shape [CanvasSurface] itself already offers.
  final CanvasCursors? cursors;
  final List<Color> cursorColors;
  final PointerMoved? onPointerMoved;

  /// Who is on this channel's call right now, already filtered for
  /// blocking - empty whenever there is no call here, or this viewer has not
  /// joined it, in which case [CanvasPresenceLayer] renders nothing.
  final List<VoiceParticipant> callParticipants;
  final CameraViewBuilder cameraViewFor;

  @override
  State<CanvasPaneBody> createState() => _CanvasPaneBodyState();
}

class _CanvasPaneBodyState extends State<CanvasPaneBody> {
  bool _activityLogOpen = false;

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
              channelId: widget.channelId,
              onClose: widget.onClose,
              tool: widget.tool,
              onToolChanged: widget.onToolChanged,
              canUndo: widget.canUndo,
              onUndo: widget.onUndo,
              canManage: widget.canManage,
              objectCount: widget.document.objectCount,
              onClear: widget.onClear,
              onPasteImage: widget.onPasteImage,
              selection: widget.document.selectedObjectId,
              onBringToFront: widget.onBringToFront,
              onSendToBack: widget.onSendToBack,
              activityLogOpen: _activityLogOpen,
              onToggleActivityLog: () =>
                  setState(() => _activityLogOpen = !_activityLogOpen),
            ),
            if (widget.error != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.s12),
                child: AppErrorState(
                  message: widget.error!,
                  onDismiss: widget.onDismissError,
                ),
              ),
            if (widget.truncated)
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
            Expanded(child: _activityLogOpen ? _panel() : _surface(tokens)),
            // Mounted regardless of the panel's own open state: browsing history is optional, hearing about it is not.
            CanvasActivityAnnouncer(activityLog: widget.activityLog),
          ],
        ),
      ),
    );
  }

  /// `document.objectCount` is the same trigger `_surface` already listens
  /// to, since a placed or removed object is exactly what changes
  /// `liveCountsByKind` too - without this, the summary would freeze at
  /// whatever it read when the panel was last opened, since nothing else
  /// rebuilds this widget on a live document change by design.
  Widget _panel() => ValueListenableBuilder<int>(
    valueListenable: widget.document.objectCount,
    builder: (context, count, child) => CanvasActivityPanel(
      activityLog: widget.activityLog,
      summary: _summary(),
    ),
  );

  Widget _surface(AppTokens tokens) => ValueListenableBuilder<int>(
    valueListenable: widget.document.objectCount,
    builder: (context, count, child) => Semantics(
      container: true,
      label: widget.loading ? 'Canvas, loading' : 'Canvas, ${_summary()}',
      child: Stack(
        children: [
          child!,
          // A blank canvas otherwise looks identical to a broken one; the screen-reader label above already says so, so this is ignored by pointers and excluded from semantics rather than doubling that node.
          if (count == 0 && !widget.loading) _emptyHint(tokens),
        ],
      ),
    ),
    child: Stack(
      children: [
        CanvasSurface(
          document: widget.document,
          ink: AppCanvasColors.annotation,
          gridLine: tokens.borderSubtle,
          // AppTokens.stripe: its own doc reserves it for exactly this state.
          placeholderFill: tokens.stripe,
          placeholderIcon: tokens.textDisabled,
          selectionOutline: tokens.accentFill,
          selectionHandleFill: tokens.surfaceRaised,
          selectionHandleBorder: tokens.accentFill,
          onStroke: widget.onStroke,
          tool: widget.tool,
          onErase: widget.onErase,
          onEraseEnd: widget.onEraseEnd,
          onSelectStart: widget.onSelectStart,
          onSelectDrag: widget.onSelectDrag,
          onSelectEnd: widget.onSelectEnd,
          cursors: widget.cursors,
          cursorColors: widget.cursorColors,
          cursorLabelFontFamily: AppFonts.sans,
          onPointerMoved: widget.onPointerMoved,
        ),
        CanvasPresenceLayer(
          document: widget.document,
          participants: widget.callParticipants,
          cameraViewFor: widget.cameraViewFor,
        ),
      ],
    ),
  );

  Widget _emptyHint(AppTokens tokens) => Positioned.fill(
    child: IgnorePointer(
      child: ExcludeSemantics(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  AppIcons.pen,
                  size: AppSizes.icon24,
                  color: tokens.textDisabled,
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  'Nothing on this canvas yet',
                  style: AppText.body.copyWith(color: tokens.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  'Draw with the pen, or paste an image from '
                  '"More canvas actions"',
                  style: AppText.caption.copyWith(color: tokens.textDisabled),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// "N objects on this canvas: X strokes, Y images" - so a screen-reader
  /// user, or anyone reading the panel's own header, can tell an empty
  /// canvas from a busy one at a glance, not only from a bare total.
  String _summary() {
    final counts = widget.document.liveCountsByKind;
    final total = counts.strokes + counts.images;
    if (total == 0) return 'no objects';
    return '$total ${total == 1 ? 'object' : 'objects'}: '
        '${counts.strokes} ${counts.strokes == 1 ? 'stroke' : 'strokes'}, '
        '${counts.images} ${counts.images == 1 ? 'image' : 'images'}';
  }
}
