// SPDX-License-Identifier: Apache-2.0
part of 'canvas_surface.dart';

/// Every pointer, scroll and scale handler [_CanvasSurfaceState.build]
/// wires up, plus the coordinate conversion and cursor choice they share.
/// A `part of` file rather than a mixin: the eraser and placement tools
/// read and write [_CanvasSurfaceState]'s own private pointer-tracking
/// fields directly, the same access `canvas_document_selection.dart`'s
/// extension already leans on for `CanvasDocument`'s private slot table.
extension _CanvasSurfaceGestures on _CanvasSurfaceState {
  /// A tool switch or a pan starting/ending are the only cursor changes,
  /// never a per-hover one - this widget deliberately never rebuilds for
  /// anything the pointer does (see the library doc), so `panning` arrives
  /// as an argument from the one [ValueListenableBuilder] that does react
  /// to it, keeping this a pure function. A disabled surface (a timed-out
  /// member) shows the plain arrow regardless of tool - except while
  /// panning, which stays available disabled or not.
  MouseCursor _cursorFor(CanvasTool tool, bool enabled, bool panning) {
    if (panning) return SystemMouseCursors.grabbing;
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

  /// Middle-mouse-button drag was chosen over right-drag for grab-to-pan:
  /// it is the near-universal convention in drawing and design tools, and a
  /// canvas object's own right-click context menu (built elsewhere) would
  /// otherwise have to tell a click from the start of a drag on every
  /// right-press, which middle-drag simply never collides with.
  bool _isPanButton(int buttons) => buttons & kMiddleMouseButton != 0;

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
    if (_isPanButton(event.buttons)) {
      // Nothing has begun for this pointer yet, so there is only a stray draft to drop, not flush.
      final hadDraft = !_draft.isEmpty;
      _draft.cancel();
      if (hadDraft) widget.onDraftEnded?.call();
      _pendingErasePoint = null;
      _beginPan(event.localPosition);
      return;
    }
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
    if (_panning.value) {
      _updatePan(event.localPosition);
      return;
    }
    if (_isPanButton(event.buttons)) {
      _interruptForPan();
      _beginPan(event.localPosition);
      return;
    }
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
    if (_panning.value) {
      _panning.value = false;
      _panFrom = null;
      return;
    }
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

  /// Starts a grab-pan from [screen], the anchor every later [_updatePan]
  /// measures its delta against. Called from [_down] when the pan button is
  /// the first (or only) one pressed, and from [_move] when it joins an
  /// already-down button - the two call sites [_isPanButton] itself is
  /// checked from, since a second button joining a mouse pointer already
  /// down is delivered as a move, never a second down.
  void _beginPan(Offset screen) {
    _panning.value = true;
    _panFrom = screen;
  }

  void _updatePan(Offset screen) {
    final from = _panFrom;
    if (from == null) return;
    final delta = screen - from;
    _panFrom = screen;
    final document = widget.document;
    final camera = document.camera;
    document.setCamera(
      camera.copyWith(
        x: camera.x - delta.dx / camera.zoom,
        y: camera.y - delta.dy / camera.zoom,
      ),
    );
  }

  /// Ends whatever tool gesture this pointer was mid-way through the moment
  /// the pan button joins it - only reachable from [_move], since [_down]
  /// has nothing to end yet. A pen draft is cancelled, not submitted as a
  /// truncated stroke or left suspended for a resume this widget never
  /// attempts - the same treatment a second touch pointer already gives it
  /// above. Erase and select flush through their own end callback instead,
  /// since both apply incrementally and an unflushed accumulator on the
  /// caller's side would otherwise sit forever unsubmitted.
  void _interruptForPan() {
    final hadDraft = !_draft.isEmpty;
    _draft.cancel();
    if (hadDraft) widget.onDraftEnded?.call();
    switch (widget.tool) {
      case CanvasTool.eraser:
        if (_pendingErasePoint case final pending?) {
          widget.onErase?.call(pending);
          _pendingErasePoint = null;
        }
        widget.onEraseEnd?.call();
      case CanvasTool.select:
        widget.onSelectEnd?.call();
      case CanvasTool.note:
      case CanvasTool.shape:
      case CanvasTool.pen:
        break;
    }
    _pendingPlacementTool = null;
    _pendingPlacementWorld = null;
  }

  /// A plain wheel notch pans vertically - the one axis a mouse wheel
  /// itself reports, and what a trackpad's own vertical swipe already
  /// produces too - while Ctrl/Cmd zooms and Shift adds the horizontal axis
  /// a single-axis wheel cannot report on its own. A trackpad's native
  /// two-axis swipe keeps panning freely in both directions unmodified,
  /// which switching the unmodified case to zoom would have broken; a
  /// middle-mouse grab-drag (see [_beginPan]) is what actually gives a
  /// plain mouse free motion in both axes, not the wheel.
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
    if (keys.isShiftPressed) {
      // Some platforms already swap a shifted wheel's delta into dx before Flutter sees it, some never do - so read whichever carries it.
      final horizontal = event.scrollDelta.dx != 0
          ? event.scrollDelta.dx
          : event.scrollDelta.dy;
      document.setCamera(
        camera.copyWith(x: camera.x + horizontal / camera.zoom),
      );
      return;
    }
    document.setCamera(
      camera.copyWith(
        x: camera.x + event.scrollDelta.dx / camera.zoom,
        y: camera.y + event.scrollDelta.dy / camera.zoom,
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
