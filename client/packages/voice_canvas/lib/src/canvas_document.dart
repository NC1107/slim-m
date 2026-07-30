// SPDX-License-Identifier: Apache-2.0
/// What a canvas surface holds: the spatial index, the camera, and the side
/// table [CanvasScene] deliberately does not carry.
///
/// A [ChangeNotifier] rather than anything Riverpod-shaped, and that is a
/// correctness property rather than a preference: a provider's value is not
/// observable until the event loop turns, so a stream physically cannot
/// deliver inside the frame that produced it. Painters take this as their
/// `repaint` listenable and no widget rebuilds when the camera moves.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'canvas_scene.dart';

/// Half-width of the bounded world, matching the server's own `WORLD_LIMIT`.
/// The canvas is large but finite (owner decision 0001).
const double worldLimit = 5000000.0;

/// Longest side one object may declare, matching the server's
/// `MAX_OBJECT_EXTENT`. A stroke is a mark, not a region.
const double maxObjectExtent = 8192.0;

/// The z-index a locally drawn stroke is given before the server's own
/// answer confirms it, so it paints above everything already known while
/// its commit is still in flight.
///
/// Written as a decimal literal rather than `1 << 40`: dart2js's bitwise
/// shift truncates to 32 bits (`JSInt._shlPositive` returns 0 past a shift
/// of 31), so on the web the shift silently evaluated to 0 - at or below
/// every real server z-index, since the first one issued is 1 - and a
/// freshly drawn stroke rendered underneath existing ink instead of above
/// it. A literal this size has no such limit: dart2js represents an
/// integer up to 2^53 as an exact double, and only the shift operators are
/// unsafe, not the value itself.
const int provisionalLocalZIndex = 1099511627776; // 2^40

/// Zoom is clamped rather than free.
///
/// The floor is not a taste call. The Phase 5 server spike measured the
/// R-Tree losing to a plain scan past about four screens of viewport and
/// recommended the client stop asking for a region wider than that, so the
/// floor keeps an ordinary pan read inside the shape the index is good at.
const double minZoom = 0.25;
const double maxZoom = 4.0;

/// Where the viewport sits in the world.
@immutable
class Camera {
  const Camera({this.x = 0, this.y = 0, this.zoom = 1});

  /// World coordinate at the viewport's top-left.
  final double x;
  final double y;
  final double zoom;

  Camera copyWith({double? x, double? y, double? zoom}) =>
      Camera(x: x ?? this.x, y: y ?? this.y, zoom: zoom ?? this.zoom);

  @override
  bool operator ==(Object other) =>
      other is Camera && other.x == x && other.y == y && other.zoom == zoom;

  @override
  int get hashCode => Object.hash(x, y, zoom);
}

/// One stroke as the wire describes it, with no JSON and no api types: the
/// app layer maps a `CanvasObject` onto this so the package stays free of
/// `slimm_api`.
@immutable
class CanvasStrokeInput {
  const CanvasStrokeInput({
    required this.id,
    required this.seq,
    required this.zIndex,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.points,
    required this.width,
    required this.colorKey,
  });

  final String id;
  final int seq;
  final int zIndex;
  final double x;
  final double y;
  final double w;
  final double h;

  /// Flat `[x0,y0,x1,y1,...]`, relative to [x] and [y], in world units.
  final List<double> points;
  final double width;

  /// A design-token role name. An unrecognised one renders as the default ink
  /// rather than being dropped, because the set is closed and a row is
  /// durable: a client too old to know a colour must still draw the mark.
  final String colorKey;
}

/// A stroke ready to paint: its [Path] is built once, at insert, in
/// object-local coordinates and reused every frame.
class CanvasStroke {
  CanvasStroke({
    required this.id,
    required this.x,
    required this.y,
    required this.path,
    required this.width,
    required this.colorKey,
    required this.zIndex,
  });

  final String id;
  final double x;
  final double y;
  final Path path;
  final double width;
  final String colorKey;

  /// Paint order, lowest first. Corrected from the server's answer once a
  /// locally drawn stroke is confirmed.
  int zIndex;

  /// False once a commit has failed for good. The painter skips it and the
  /// grid keeps a stale entry, which costs one extra candidate: [UniformGrid]
  /// has no `remove` and a full rebuild costs over a millisecond, so this
  /// slice does not touch the index for something this rare.
  bool alive = true;
}

/// The document: index, camera, strokes, and dedupe by id.
class CanvasDocument extends ChangeNotifier {
  CanvasDocument();

  final CanvasScene scene = CanvasScene();
  final List<CanvasStroke> _strokes = <CanvasStroke>[];
  final Map<String, int> _slotById = <String, int>{};
  final List<int> _order = <int>[];

  Camera _camera = const Camera();
  Size _viewport = Size.zero;

  /// Bumped whenever the set of objects changes, never when the camera moves,
  /// so an announcement can be rebuilt on content without firing at pan rate.
  final ValueNotifier<int> objectCount = ValueNotifier<int>(0);

  Camera get camera => _camera;
  Size get viewport => _viewport;
  CanvasStroke strokeAt(int slot) => _strokes[slot];
  bool knows(String id) => _slotById.containsKey(id);

  /// Slots the last cull kept, in paint order.
  ///
  /// Sorted here rather than taken as the cull emits them: [UniformGrid]
  /// answers in cell order on one branch and slot order on the other, and it
  /// switches between them on zoom, so painting the raw cull would re-layer
  /// overlapping ink as somebody zoomed across the adaptive threshold. The
  /// server pays a sort for `(z_index, seq)` and this is where that answer is
  /// honoured rather than thrown away.
  List<int> get paintOrder {
    _order
      ..clear()
      ..addAll(scene.visible.where((slot) => _strokes[slot].alive));
    _order.sort((a, b) => _strokes[a].zIndex.compareTo(_strokes[b].zIndex));
    return _order;
  }

  /// Adds a stroke, or returns the slot it already occupies.
  ///
  /// Dedupe by id is what makes every fetch path safe to repeat: place is
  /// idempotent server-side, so a duplicate from a pan, a live frame or a
  /// reconnect is a no-op here rather than a second mark.
  int applyPlaced(CanvasStrokeInput input) {
    final known = _slotById[input.id];
    if (known != null) {
      _strokes[known].zIndex = input.zIndex;
      return known;
    }
    final path = Path();
    for (var i = 0; i + 1 < input.points.length; i += 2) {
      final px = input.points[i];
      final py = input.points[i + 1];
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    if (input.points.length == 2) {
      path.lineTo(input.points[0], input.points[1]);
    }
    final slot = scene.add(
      input.x,
      input.y,
      input.x + input.w,
      input.y + input.h,
    );
    _strokes.add(
      CanvasStroke(
        id: input.id,
        x: input.x,
        y: input.y,
        path: path,
        width: input.width,
        colorKey: input.colorKey,
        zIndex: input.zIndex,
      ),
    );
    _slotById[input.id] = slot;
    objectCount.value = objectCount.value + 1;
    return slot;
  }

  /// Marks a stroke as never having landed.
  void kill(String id) {
    final slot = _slotById[id];
    if (slot == null || !_strokes[slot].alive) return;
    _strokes[slot].alive = false;
    objectCount.value = objectCount.value - 1;
  }

  /// Re-culls against the current camera and repaints.
  ///
  /// Separate from [applyPlaced] so a snapshot of several hundred objects
  /// costs one cull and one repaint rather than one of each per object, the
  /// same reason [CanvasScene.add] does not notify.
  void refresh() => _reculled();

  /// Moves the camera, clamped so the view stays inside the bounded world and
  /// the zoom inside the range a viewport read is sized for.
  void setCamera(Camera next) {
    _camera = _clamp(next);
    _reculled();
  }

  void setViewport(Size size) {
    if (size == _viewport) return;
    _viewport = size;
    _camera = _clamp(_camera);
    _reculled();
  }

  /// The world rectangle currently on screen.
  Rect get worldView => Rect.fromLTWH(
        _camera.x,
        _camera.y,
        _viewport.width / _camera.zoom,
        _viewport.height / _camera.zoom,
      );

  Camera _clamp(Camera next) {
    final zoom = next.zoom.clamp(minZoom, maxZoom);
    final w = _viewport.width / zoom;
    final h = _viewport.height / zoom;
    final maxX = math.max(-worldLimit, worldLimit - w);
    final maxY = math.max(-worldLimit, worldLimit - h);
    return Camera(
      x: next.x.clamp(-worldLimit, maxX),
      y: next.y.clamp(-worldLimit, maxY),
      zoom: zoom,
    );
  }

  void _reculled() {
    final view = worldView;
    scene.setViewport(view.left, view.top, view.right, view.bottom);
    notifyListeners();
  }

  @override
  void dispose() {
    objectCount.dispose();
    scene.dispose();
    super.dispose();
  }
}
