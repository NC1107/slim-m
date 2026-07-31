// SPDX-License-Identifier: Apache-2.0
/// The wire-facing shapes [CanvasDocument] stores: the camera, the input a
/// placement carries, and the stroke ready to paint.
///
/// Split out of `canvas_document.dart`, which was past the 300-line review
/// budget; `canvas_document.dart` re-exports this library, so nothing that
/// imported it for these types has to change.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// How many erased ids [CanvasDocument] remembers so an in-flight fetch
/// cannot resurrect one, matching the server's own `MAX_OBJECTS_PER_CHANNEL`:
/// no viewport read in flight can name more live ids than the channel's own
/// ceiling.
const int maxRemovedIdsTracked = 20000;

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
    required this.points,
    required this.width,
    required this.colorKey,
    required this.zIndex,
    required this.seq,
  });

  final String id;
  final double x;
  final double y;
  final Path path;
  final double width;
  final String colorKey;

  /// Every point in absolute world coordinates, for hit testing against a
  /// world-space pointer with no per-call offset arithmetic.
  ///
  /// `Float32List` rather than `List<double>`: a boxed double runs roughly
  /// 16 bytes against 4, a 4x difference at the 20,000-object ceiling, and
  /// hit testing does not need `double` precision at world scale.
  final Float32List points;

  /// Paint order, lowest first. Corrected from the server's answer once a
  /// locally drawn stroke is confirmed.
  int zIndex;

  /// The op that placed this object, `0` until the server confirms it.
  /// [CanvasDocument.clearBelow] spares `0` deliberately, or a clear in
  /// flight erases ink as it is drawn.
  int seq;

  /// False once a commit has failed for good. The painter skips it; the
  /// grid still finds the slot, since [CanvasDocument.kill] means "this
  /// commit never landed" and is a different thing from a real removal.
  bool alive = true;
}
