// SPDX-License-Identifier: Apache-2.0
/// The drawing surface: three repaint boundaries, raw pointer input, and no
/// widget rebuild for anything the camera or the pointer does.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'canvas_cursors.dart';
import 'canvas_document.dart';
import 'canvas_painters.dart';
import 'selection_painter.dart';

/// A pen stroke the surface has finished and wants committed.
typedef StrokeCommitted = void Function(List<Offset> worldPoints);

/// This pointer moved to a world position, on every hover and drag alike.
/// The caller decides whether and how often to relay it.
typedef PointerMoved = void Function(Offset worldPoint);

/// Which gesture a single pointer draws.
///
/// Three tools is still a toggle row, not a dock: nothing here needs a
/// picker with more options than fit on one line, and a floating panel would
/// only add a container around the same three buttons.
enum CanvasTool { pen, eraser, select }

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
    this.onEraseEnd,
    this.onSelectStart,
    this.onSelectDrag,
    this.onSelectEnd,
    this.tool = CanvasTool.pen,
    this.strokeWidth = 3,
    this.enabled = true,
    this.cursors,
    this.cursorColors = const [],
    this.cursorLabelFontFamily,
    this.onPointerMoved,
    this.placeholderFill = const Color(0xFFB9C0C8),
    this.placeholderIcon = const Color(0xFF6C757E),
    this.selectionOutline,
    this.selectionHandleFill,
    this.selectionHandleBorder,
  });

  final CanvasDocument document;
  final Color ink;
  final Color gridLine;

  /// The selection outline and resize-handle colours. Null renders no
  /// selection layer at all, the same "pay nothing for it unwired" choice
  /// [cursors] already makes - a caller with no notion of selection (a test,
  /// a read-only viewer) does not pay for the extra paint pass.
  final Color? selectionOutline;
  final Color? selectionHandleFill;
  final Color? selectionHandleBorder;

  /// The muted fill and glyph colour for an image whose bytes could not be
  /// fetched or decoded. See [StrokePainter]'s own doc for why this draws
  /// something rather than nothing.
  final Color placeholderFill;
  final Color placeholderIcon;
  final StrokeCommitted onStroke;
  final double strokeWidth;

  /// Other participants' live pointers, painted over the ink. Null renders
  /// no cursor layer at all, so a caller that has not wired remote cursors up
  /// yet (or a test that has no opinion about them) pays nothing for it.
  final CanvasCursors? cursors;

  /// The closed colour set [cursors] indexes into. Meaningless without
  /// [cursors], and ignored when it is null.
  final List<Color> cursorColors;

  /// The app's own type family for a cursor's name chip. Null draws
  /// Flutter's platform default rather than the product's own type, the same
  /// reason [ink] and [cursorColors] arrive as plain values rather than this
  /// package reaching for a design system it does not depend on.
  final String? cursorLabelFontFamily;

  /// Fires on every hover or drag move, drawing or not, in world
  /// coordinates. The caller decides whether, and how often, to relay this
  /// onward - this widget applies no throttle of its own so a test can
  /// assert on every call without needing a fake clock.
  final PointerMoved? onPointerMoved;

  /// Which gesture a pointer draws. Resolving a world point to an object is
  /// the caller's job, over [onErase], so this widget stays free of any
  /// notion of hit testing or permission.
  final CanvasTool tool;

  /// Fires once per pointer-down and again on every move while [tool] is
  /// [CanvasTool.eraser], so a drag can wipe through several objects the way
  /// a moderator clearing a defaced region expects.
  final ValueChanged<Offset>? onErase;

  /// Fires once the whole erase gesture ends - the last pointer lifting,
  /// not the first of several in a multi-touch pan - so the caller can
  /// submit whatever [onErase] collected as one removal rather than one per
  /// point, which is what makes undoing an erase drag a single op.
  final VoidCallback? onEraseEnd;

  /// Fires on pointer-down while [tool] is [CanvasTool.select], in world
  /// coordinates. Resolving whether an object was actually picked up (and
  /// which one) is the caller's job, the same division [onErase] already
  /// draws, so this widget carries no notion of hit testing either.
  final ValueChanged<Offset>? onSelectStart;

  /// Fires on every pointer move while [tool] is [CanvasTool.select] and a
  /// drag is under way, in world coordinates.
  final ValueChanged<Offset>? onSelectDrag;

  /// Fires once a select-drag ends - the last pointer lifting - so the
  /// caller can commit the final position as one op rather than one per
  /// move, the same shape [onEraseEnd] already uses.
  final VoidCallback? onSelectEnd;

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
    placeholderFill: widget.placeholderFill,
    placeholderIcon: widget.placeholderIcon,
  );
  late final DraftPainter _draftPainter = DraftPainter(
    draft: _draft,
    document: widget.document,
    ink: widget.ink,
    width: widget.strokeWidth,
  );
  late final CursorPainter? _cursorPainter = widget.cursors == null
      ? null
      : CursorPainter(
          cursors: widget.cursors!,
          document: widget.document,
          colors: widget.cursorColors,
          labelFontFamily: widget.cursorLabelFontFamily,
        );
  late final SelectionPainter? _selectionPainter = widget.selectionOutline ==
          null
      ? null
      : SelectionPainter(
          document: widget.document,
          outline: widget.selectionOutline!,
          handleFill: widget.selectionHandleFill ?? widget.selectionOutline!,
          handleBorder:
              widget.selectionHandleBorder ?? widget.selectionOutline!,
        );

  int _pointers = 0;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  /// The one cursor a tool switch justifies changing, never a per-hover one:
  /// this widget deliberately never rebuilds for anything the pointer does
  /// (see the library doc), and a cursor keyed to hover position would need
  /// exactly that. A disabled surface (a timed-out member) shows the plain
  /// arrow regardless of tool, since nothing here would answer a click.
  MouseCursor _cursorFor(CanvasTool tool, bool enabled) {
    if (!enabled) return SystemMouseCursors.basic;
    return switch (tool) {
      CanvasTool.pen || CanvasTool.eraser => SystemMouseCursors.precise,
      CanvasTool.select => SystemMouseCursors.grab,
    };
  }

  Offset _toWorld(Offset screen) {
    final camera = widget.document.camera;
    return Offset(
      camera.x + screen.dx / camera.zoom,
      camera.y + screen.dy / camera.zoom,
    );
  }

  void _down(PointerDownEvent event) {
    widget.onPointerMoved?.call(_toWorld(event.localPosition));
    _pointers++;
    if (_pointers > 1) {
      _draft.cancel();
      return;
    }
    if (!widget.enabled) return;
    switch (widget.tool) {
      case CanvasTool.eraser:
        widget.onErase?.call(_toWorld(event.localPosition));
      case CanvasTool.select:
        widget.onSelectStart?.call(_toWorld(event.localPosition));
      case CanvasTool.pen:
        _draft.begin(event.localPosition);
    }
  }

  void _move(PointerMoveEvent event) {
    widget.onPointerMoved?.call(_toWorld(event.localPosition));
    if (_pointers != 1 || !widget.enabled) return;
    switch (widget.tool) {
      case CanvasTool.eraser:
        widget.onErase?.call(_toWorld(event.localPosition));
      case CanvasTool.select:
        widget.onSelectDrag?.call(_toWorld(event.localPosition));
      case CanvasTool.pen:
        _draft.extend(event.localPosition);
    }
  }

  /// A pointer moving with nothing pressed - drawing or erasing never
  /// happens here, only the position report a mouse (not a touch, which
  /// never hovers) gets for free.
  void _hover(PointerHoverEvent event) {
    widget.onPointerMoved?.call(_toWorld(event.localPosition));
  }

  void _up(PointerEvent event) {
    _pointers = (_pointers - 1).clamp(0, 10);
    switch (widget.tool) {
      case CanvasTool.eraser:
        if (_pointers == 0) widget.onEraseEnd?.call();
      case CanvasTool.select:
        if (_pointers == 0) widget.onSelectEnd?.call();
      case CanvasTool.pen:
        if (_draft.isEmpty) return;
        final screen = _draft.take();
        if (screen.length < 2) return;
        widget.onStroke(screen.map(_toWorld).toList(growable: false));
    }
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
        return MouseRegion(
          cursor: _cursorFor(widget.tool, widget.enabled),
          child: Listener(
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerHover: _hover,
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
                  if (_selectionPainter case final selectionPainter?)
                    RepaintBoundary(
                        child: CustomPaint(painter: selectionPainter)),
                  if (_cursorPainter case final cursorPainter?)
                    RepaintBoundary(child: CustomPaint(painter: cursorPainter)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
