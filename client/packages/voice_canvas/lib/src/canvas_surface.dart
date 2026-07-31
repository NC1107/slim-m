// SPDX-License-Identifier: Apache-2.0
/// The drawing surface: three repaint boundaries, raw pointer input, and no
/// widget rebuild for anything the camera or the pointer does.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'canvas_document.dart';
import 'canvas_painters.dart';

/// A pen stroke the surface has finished and wants committed.
typedef StrokeCommitted = void Function(List<Offset> worldPoints);

/// Which gesture a single pointer draws.
///
/// Two tools is a toggle, not a dock: a picker over one item is a control
/// that cannot change anything.
enum CanvasTool { pen, eraser }

/// The canvas itself.
///
/// Input is a raw [Listener] rather than a gesture recogniser for drawing:
/// a recogniser waits to see whether the gesture is something else, and the
/// design language is explicit that nothing under a live cursor may lag.
/// Panning and zooming go through [GestureDetector.onScaleUpdate], which only
/// takes over once a second pointer is down - and a second pointer cancels the
/// draft outright, so a two-finger pan cannot leave a stray mark.
class CanvasSurface extends StatefulWidget {
  const CanvasSurface({
    super.key,
    required this.document,
    required this.ink,
    required this.gridLine,
    required this.onStroke,
    this.onErase,
    this.tool = CanvasTool.pen,
    this.strokeWidth = 3,
    this.enabled = true,
  });

  final CanvasDocument document;
  final Color ink;
  final Color gridLine;
  final StrokeCommitted onStroke;
  final double strokeWidth;

  /// Which gesture a pointer draws. Resolving a world point to an object is
  /// the caller's job, over [onErase], so this widget stays free of any
  /// notion of hit testing or permission.
  final CanvasTool tool;

  /// Fires once per pointer-down and again on every move while [tool] is
  /// [CanvasTool.eraser], so a drag can wipe through several objects the way
  /// a moderator clearing a defaced region expects.
  final ValueChanged<Offset>? onErase;

  /// False freezes the pen and leaves pan and zoom alone, which is what a
  /// timed-out member gets: they keep seeing the canvas and cannot add to it.
  final bool enabled;

  @override
  State<CanvasSurface> createState() => _CanvasSurfaceState();
}

class _CanvasSurfaceState extends State<CanvasSurface> {
  final DraftStroke _draft = DraftStroke();
  late final GridPainter _grid = GridPainter(
    document: widget.document,
    line: widget.gridLine,
  );
  late final StrokePainter _strokes = StrokePainter(
    document: widget.document,
    ink: widget.ink,
  );
  late final DraftPainter _draftPainter = DraftPainter(
    draft: _draft,
    document: widget.document,
    ink: widget.ink,
    width: widget.strokeWidth,
  );

  int _pointers = 0;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Offset _toWorld(Offset screen) {
    final camera = widget.document.camera;
    return Offset(
      camera.x + screen.dx / camera.zoom,
      camera.y + screen.dy / camera.zoom,
    );
  }

  void _down(PointerDownEvent event) {
    _pointers++;
    if (_pointers > 1) {
      _draft.cancel();
      return;
    }
    if (!widget.enabled) return;
    if (widget.tool == CanvasTool.eraser) {
      widget.onErase?.call(_toWorld(event.localPosition));
      return;
    }
    _draft.begin(event.localPosition);
  }

  void _move(PointerMoveEvent event) {
    if (_pointers != 1 || !widget.enabled) return;
    if (widget.tool == CanvasTool.eraser) {
      widget.onErase?.call(_toWorld(event.localPosition));
      return;
    }
    _draft.extend(event.localPosition);
  }

  void _up(PointerEvent event) {
    _pointers = (_pointers - 1).clamp(0, 10);
    if (widget.tool == CanvasTool.eraser) return;
    if (_draft.isEmpty) return;
    final screen = _draft.take();
    if (screen.length < 2) return;
    widget.onStroke(screen.map(_toWorld).toList(growable: false));
  }

  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final document = widget.document;
    final camera = document.camera;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed) {
      final factor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
      _zoomAbout(event.localPosition, camera.zoom * factor);
      return;
    }
    final dx =
        keys.isShiftPressed ? event.scrollDelta.dy : event.scrollDelta.dx;
    final dy = keys.isShiftPressed ? 0.0 : event.scrollDelta.dy;
    document.setCamera(
      camera.copyWith(
        x: camera.x + dx / camera.zoom,
        y: camera.y + dy / camera.zoom,
      ),
    );
  }

  void _zoomAbout(Offset focal, double zoom) {
    final document = widget.document;
    final before = _toWorld(focal);
    document.setCamera(document.camera.copyWith(zoom: zoom));
    final after = _toWorld(focal);
    final camera = document.camera;
    document.setCamera(
      camera.copyWith(
        x: camera.x + (before.dx - after.dx),
        y: camera.y + (before.dy - after.dy),
      ),
    );
  }

  Camera? _scaleStart;
  Offset? _scaleFocalWorld;

  void _scaleBegin(ScaleStartDetails details) {
    _scaleStart = widget.document.camera;
    _scaleFocalWorld = _toWorld(details.localFocalPoint);
  }

  void _scaleUpdate(ScaleUpdateDetails details) {
    final start = _scaleStart;
    final anchor = _scaleFocalWorld;
    if (start == null || anchor == null || details.pointerCount < 2) return;
    final document = widget.document;
    document.setCamera(start.copyWith(zoom: start.zoom * details.scale));
    final camera = document.camera;
    final focal = details.localFocalPoint;
    document.setCamera(
      camera.copyWith(
        x: anchor.dx - focal.dx / camera.zoom,
        y: anchor.dy - focal.dy / camera.zoom,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        // Outside the paint pass on purpose: setting it during paint would mutate what is being painted.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => widget.document.setViewport(size),
        );
        return Listener(
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          onPointerSignal: _signal,
          child: GestureDetector(
            onScaleStart: _scaleBegin,
            onScaleUpdate: _scaleUpdate,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(child: CustomPaint(painter: _grid)),
                RepaintBoundary(child: CustomPaint(painter: _strokes)),
                RepaintBoundary(child: CustomPaint(painter: _draftPainter)),
              ],
            ),
          ),
        );
      },
    );
  }
}
