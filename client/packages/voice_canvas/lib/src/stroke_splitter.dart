// SPDX-License-Identifier: Apache-2.0
/// Turning a drawn polyline into objects the server will accept.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'canvas_document.dart';

/// One segment of a drawn stroke, ready to be sent.
@immutable
class StrokeSegment {
  const StrokeSegment({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.points,
  });

  final double x;
  final double y;
  final double w;
  final double h;

  /// Relative to [x] and [y], quantised, ready to encode.
  final List<double> points;
}

/// Splits a drawn polyline into objects the server will accept.
///
/// Budgeted by *encoded bytes*, never by a point count, and that is the whole
/// reason this is a function with a test rather than a constant. A point count
/// says nothing about how long the JSON is: Dart emits shortest-round-trip
/// doubles, so 512 unquantised coordinates run from four characters to
/// seventeen and a legal-looking stroke straddles the ceiling. Over it the
/// server answers 400 and ink already on the drawer's own screen disappears,
/// which is the worst failure this surface has.
///
/// Coordinates are quantised to two decimals first, which bounds a point to
/// nine characters given [maxObjectExtent], and each segment repeats the
/// previous one's last point so a split leaves no visible seam.
List<StrokeSegment> splitStroke(
  List<Offset> worldPoints, {
  int maxPropsBytes = 3500,
}) {
  if (worldPoints.isEmpty) return const <StrokeSegment>[];
  final segments = <StrokeSegment>[];
  var start = 0;
  var end = 1;
  while (start < worldPoints.length) {
    var candidate = end;
    while (candidate < worldPoints.length) {
      final next = candidate + 1;
      if (_encodedLength(worldPoints, start, next) > maxPropsBytes ||
          !_withinExtent(worldPoints, start, next)) {
        break;
      }
      candidate = next;
    }
    // At least two points, or a single tap never becomes a mark at all.
    final stop = math.max(candidate, math.min(start + 2, worldPoints.length));
    segments.add(_segment(worldPoints, start, stop));
    if (stop >= worldPoints.length) break;
    start = stop - 1;
    end = start + 1;
  }
  return segments;
}

double _quantise(double v) => (v * 100).roundToDouble() / 100;

bool _withinExtent(List<Offset> points, int start, int stop) {
  final box = _bounds(points, start, stop);
  return box.width <= maxObjectExtent && box.height <= maxObjectExtent;
}

Rect _bounds(List<Offset> points, int start, int stop) {
  var minX = points[start].dx;
  var minY = points[start].dy;
  var maxX = minX;
  var maxY = minY;
  for (var i = start; i < stop; i++) {
    minX = math.min(minX, points[i].dx);
    minY = math.min(minY, points[i].dy);
    maxX = math.max(maxX, points[i].dx);
    maxY = math.max(maxY, points[i].dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

StrokeSegment _segment(List<Offset> points, int start, int stop) {
  final box = _bounds(points, start, stop);
  final x = _quantise(box.left);
  final y = _quantise(box.top);
  final flat = <double>[];
  for (var i = start; i < stop; i++) {
    flat
      ..add(_quantise(points[i].dx - x))
      ..add(_quantise(points[i].dy - y));
  }
  return StrokeSegment(
    x: x,
    y: y,
    w: _quantise(box.width),
    h: _quantise(box.height),
    points: flat,
  );
}

int _encodedLength(List<Offset> points, int start, int stop) =>
    jsonEncode(_segment(points, start, stop).points).length;
