// SPDX-License-Identifier: Apache-2.0
/// The AR-glasses interaction the owner asked for by name: a camera or
/// screen-share tile you can drag anywhere in the canvas's own world space,
/// resize with a grip, lock so a drawing tool reaches through it, or hide.
///
/// Deliberately not built on the drag-and-resize state machine
/// `canvas_ops_controller_select.dart` already drives for a real
/// [CanvasObjectKind] - a presence tile is not one of those (see
/// `canvas_presence_layer.dart`'s own doc for why), so it owns a short,
/// self-contained gesture handler instead, the same shape the self bubble's
/// old screen-anchored drag already used before this file replaced it.
///
/// [CanvasPresenceManipulableTile.locked] wraps only the content in
/// [IgnorePointer]: the resize grip disappears (nothing to resize while
/// locked) but the lock control itself never does, or a locked tile would be
/// a dead end with no way back.
///
/// [CanvasPresenceManipulableTile.sentToBack] never touches this widget's
/// own layout, gesture handling or paint position at all - see
/// `canvas_presence_layer.dart`'s own doc for why. Only [child] differs
/// (an invisible placeholder when sent to back, the real content
/// otherwise), so the drag area, resize grip and corner controls stay
/// exactly where a person last saw them, whichever side of the drawing
/// surface the tile's own pixels are currently painting on.
///
/// An unlocked tile's opaque hit test also has to answer for two things it
/// does not otherwise implement, both because `CanvasSurface` beneath it
/// never receives a down event a tile has already absorbed - true
/// regardless of [sentToBack], since this widget's own interactive shell
/// stays in front of `CanvasSurface` at every depth. A middle-mouse
/// grab-pan is one - `canvas_surface_gestures.dart` honours it everywhere
/// else on the canvas, and Flutter's hit test cannot forward just that
/// button selectively (opacity is decided once per pointer, before its
/// buttons are read), so this widget replicates `_updatePan`'s own delta
/// math directly against [document]. The other is simpler: every pointer
/// this tile absorbs is reported to [CanvasDocument.externalPointers], or
/// `CanvasSurface`'s own pinch-cancellation guard would only ever see one
/// finger of a two-finger touch that happened to land partly on a tile, and
/// place on it as though no second finger had come down at all.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'canvas_presence_geometry.dart' show presenceScreenRect;
import 'canvas_presence_tile_controls.dart';

/// The world-space box a resize may not shrink below or grow past - small
/// enough that the name badge and controls still fit, large enough that a
/// single tile can never swallow a typical viewport.
const canvasPresenceTileMinSize = Size(72, 54);
const canvasPresenceTileMaxSize = Size(720, 540);

class CanvasPresenceManipulableTile extends StatefulWidget {
  const CanvasPresenceManipulableTile({
    super.key,
    required this.worldRect,
    required this.camera,
    required this.locked,
    required this.sentToBack,
    required this.onRectChanged,
    required this.onToggleLocked,
    required this.onToggleSentToBack,
    required this.onHide,
    required this.semanticLabel,
    required this.document,
    required this.child,
  });

  final Rect worldRect;
  final Camera camera;
  final bool locked;

  /// Whether this tile's own content currently paints behind
  /// [CanvasSurface] rather than above it - purely informational here, for
  /// the corner control's own icon and label; see this file's own doc for
  /// why depth never changes anything else about this widget.
  final bool sentToBack;

  /// Only read for a middle-mouse grab-pan starting on this tile - see the
  /// library doc for why that one gesture is handled here directly rather
  /// than left to reach `CanvasSurface` on its own.
  final CanvasDocument document;

  /// Fired on every drag/resize update, in world space - the caller owns
  /// persisting it (`CanvasPresenceTileOverrides.setRect`), this widget owns
  /// only the arithmetic and the live-while-dragging feel.
  final ValueChanged<Rect> onRectChanged;
  final VoidCallback onToggleLocked;
  final VoidCallback onToggleSentToBack;
  final VoidCallback onHide;
  final String semanticLabel;
  final Widget child;

  @override
  State<CanvasPresenceManipulableTile> createState() =>
      _CanvasPresenceManipulableTileState();
}

class _CanvasPresenceManipulableTileState
    extends State<CanvasPresenceManipulableTile> {
  /// Non-null only while a drag or resize is in flight. Tracking it locally,
  /// rather than trusting [CanvasPresenceManipulableTile.worldRect] to have
  /// already round-tripped through the caller's own state and back by the
  /// next pointer event, is what keeps a fast drag from stuttering on a
  /// rebuild that has not landed yet.
  Rect? _liveRect;

  Rect get _rect => _liveRect ?? widget.worldRect;

  void _drag(DragUpdateDetails details) {
    final next = _rect.shift(details.delta / widget.camera.zoom);
    setState(() => _liveRect = next);
    widget.onRectChanged(next);
  }

  void _resize(DragUpdateDetails details) {
    final delta = details.delta / widget.camera.zoom;
    final current = _rect;
    final width = (current.width + delta.dx).clamp(
      canvasPresenceTileMinSize.width,
      canvasPresenceTileMaxSize.width,
    );
    final height = (current.height + delta.dy).clamp(
      canvasPresenceTileMinSize.height,
      canvasPresenceTileMaxSize.height,
    );
    final next = Rect.fromLTWH(current.left, current.top, width, height);
    setState(() => _liveRect = next);
    widget.onRectChanged(next);
  }

  void _settle(DragEndDetails details) => setState(() => _liveRect = null);

  /// This tile's own pan pointer, so an unrelated second pointer's own
  /// button cannot steer or end a grab it did not start - the same guard
  /// `_beginPan`'s own doc gives `CanvasSurface`.
  int? _panPointer;
  Offset? _panFrom;

  /// Every pointer this tile has told [CanvasExternalPointers] about but not
  /// yet told it left - see that class's own doc for why `CanvasSurface`
  /// needs to hear about a pointer it never itself received a down event
  /// for. A set, not a count, because [dispose] has to balance exactly the
  /// pointers this instance actually added, never a guess.
  final Set<int> _countedPointers = {};

  bool _isPanButton(int buttons) => buttons & kMiddleMouseButton != 0;

  void _pointerDown(PointerDownEvent event) {
    _countedPointers.add(event.pointer);
    widget.document.externalPointers.add();
    if (_panPointer == null && _isPanButton(event.buttons)) {
      _panPointer = event.pointer;
      _panFrom = event.position;
    }
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _panPointer) return;
    if (!_isPanButton(event.buttons)) {
      _panPointer = null;
      _panFrom = null;
      return;
    }
    final from = _panFrom!;
    final delta = event.position - from;
    _panFrom = event.position;
    final camera = widget.document.camera;
    widget.document.setCamera(
      camera.copyWith(
        x: camera.x - delta.dx / camera.zoom,
        y: camera.y - delta.dy / camera.zoom,
      ),
    );
  }

  void _pointerUp(PointerEvent event) {
    if (_countedPointers.remove(event.pointer)) {
      widget.document.externalPointers.remove();
    }
    if (event.pointer == _panPointer) {
      _panPointer = null;
      _panFrom = null;
    }
  }

  @override
  void dispose() {
    for (final _ in _countedPointers) {
      widget.document.externalPointers.remove();
    }
    _countedPointers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    final screen = presenceScreenRect(rect, widget.camera);
    return Positioned(
      left: screen.left,
      top: screen.top,
      width: screen.width,
      height: screen.height,
      child: Listener(
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMove,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerUp,
        child: Semantics(
          container: true,
          label: widget.semanticLabel,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IgnorePointer(
                ignoring: widget.locked,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // A no-op, not an omission: a right-click on a tile must never leak to a canvas object underneath it, `canvas_self_presence_overlay.dart`'s old precedent for this exact absorption.
                  onSecondaryTapUp: (_) {},
                  onPanUpdate: _drag,
                  onPanEnd: _settle,
                  child: widget.child,
                ),
              ),
              if (!widget.locked)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: TileResizeGrip(onUpdate: _resize, onEnd: _settle),
                ),
              Positioned(
                right: 2,
                top: 2,
                child: TileControls(
                  locked: widget.locked,
                  sentToBack: widget.sentToBack,
                  onToggleLocked: widget.onToggleLocked,
                  onToggleSentToBack: widget.onToggleSentToBack,
                  onHide: widget.onHide,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
