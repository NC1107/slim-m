// SPDX-License-Identifier: Apache-2.0
part of 'canvas_surface.dart';

/// Every pointer, scroll and scale handler [_CanvasSurfaceState.build]
/// wires up, plus the coordinate conversion and cursor choice they share.
/// A `part of` file rather than a mixin: the eraser and placement tools
/// read and write [_CanvasSurfaceState]'s own private pointer-tracking
/// fields directly, the same access `canvas_document_selection.dart`'s
/// extension already leans on for `CanvasDocument`'s private slot table.
extension _CanvasSurfaceGestures on _CanvasSurfaceState {
  /// The one cursor a tool switch justifies changing, never a per-hover one:
  /// this widget deliberately never rebuilds for anything the pointer does
  /// (see the library doc), and a cursor keyed to hover position would need
  /// exactly that. A disabled surface (a timed-out member) shows the plain
  /// arrow regardless of tool, since nothing here would answer a click.
  MouseCursor _cursorFor(CanvasTool tool, bool enabled) {
    if (!enabled) return SystemMouseCursors.basic;
    return switch (tool) {
      CanvasTool.pen ||
      CanvasTool.eraser ||
      CanvasTool.note ||
      CanvasTool.shape =>
        SystemMouseCursors.precise,
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
      final hadDraft = !_draft.isEmpty;
      _draft.cancel();
      if (hadDraft) widget.onDraftEnded?.call();
      _pendingErasePoint = null;
      return;
    }
    if (!widget.enabled) return;
    switch (widget.tool) {
      case CanvasTool.eraser:
        _pendingErasePoint = _toWorld(event.localPosition);
      case CanvasTool.select:
        widget.onSelectStart?.call(_toWorld(event.localPosition));
      case CanvasTool.note:
        _pendingPlacementTool = CanvasTool.note;
        _pendingPlacementWorld = _toWorld(event.localPosition);
      case CanvasTool.shape:
        _pendingPlacementTool = CanvasTool.shape;
        _pendingPlacementWorld = _toWorld(event.localPosition);
      case CanvasTool.pen:
        _draft.begin(event.localPosition);
        widget.onDraftPoint?.call(_toWorld(event.localPosition));
    }
  }

  void _move(PointerMoveEvent event) {
    widget.onPointerMoved?.call(_toWorld(event.localPosition));
    if (_pointers != 1 || !widget.enabled) return;
    switch (widget.tool) {
      case CanvasTool.eraser:
        if (_pendingErasePoint case final pending?) {
          widget.onErase?.call(pending);
          _pendingErasePoint = null;
        }
        widget.onErase?.call(_toWorld(event.localPosition));
      case CanvasTool.select:
        widget.onSelectDrag?.call(_toWorld(event.localPosition));
      case CanvasTool.note:
      case CanvasTool.shape:
        break;
      case CanvasTool.pen:
        _draft.extend(event.localPosition);
        widget.onDraftPoint?.call(_toWorld(event.localPosition));
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
    _resolvePendingPlacement();
    switch (widget.tool) {
      case CanvasTool.eraser:
        if (_pendingErasePoint case final pending?) {
          widget.onErase?.call(pending);
          _pendingErasePoint = null;
        }
        if (_pointers == 0) widget.onEraseEnd?.call();
      case CanvasTool.select:
        if (_pointers == 0) widget.onSelectEnd?.call();
      case CanvasTool.note:
      case CanvasTool.shape:
        break;
      case CanvasTool.pen:
        if (_draft.isEmpty) return;
        final screen = _draft.take();
        widget.onDraftEnded?.call();
        if (screen.length < 2) return;
        widget.onStroke(screen.map(_toWorld).toList(growable: false));
    }
  }

  /// Fires whichever placement [_down] armed, at the point it was armed
  /// with, only on the [_up] that drops [_pointers] to zero. Runs once per
  /// lifted pointer and consumes pending state on its first call regardless
  /// of [_pointers], so any second pointer having touched down - landing
  /// that first call at a nonzero count - is what stops this ever firing.
  void _resolvePendingPlacement() {
    final tool = _pendingPlacementTool;
    final world = _pendingPlacementWorld;
    if (tool == null || world == null) return;
    _pendingPlacementTool = null;
    _pendingPlacementWorld = null;
    if (_pointers != 0) return;
    switch (tool) {
      case CanvasTool.note:
        widget.onNotePlace?.call(world);
      case CanvasTool.shape:
        widget.onShapePlace?.call(world);
      case CanvasTool.pen:
      case CanvasTool.eraser:
      case CanvasTool.select:
        break;
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
}
