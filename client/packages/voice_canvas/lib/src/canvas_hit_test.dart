// SPDX-License-Identifier: Apache-2.0
/// Which stroke, if any, a pointer landed on.
///
/// Nearest-segment-within-tolerance against a stroke's own points, never its
/// bounding box: a long diagonal stroke's box covers area its ink never
/// touches, so testing the box would let an eraser take out a neighbour the
/// drawn line never crossed.
library;

import 'dart:typed_data';

import 'package:flutter/painting.dart';

import 'canvas_document.dart';
import 'spatial_grid.dart';

/// A stroke's bounding box holds only its path extent, not its stroke width,
/// so a thin, straight stroke can have a zero-height box the pointer must
/// still reach through this margin. Generous on purpose: there is no ceiling
/// on pen width small enough to make a tighter pad safe.
const double _cullPad = 64;

/// Finds the topmost live stroke within tolerance of [world], or null.
///
/// Candidates come from a small cull around the pointer, never a full scan.
/// They are tested highest z-index first, so an eraser takes the same
/// stroke a viewer sees on top, and the first one within its own
/// `width / 2 + slop` wins.
String? hitTestStroke(
  CanvasDocument document,
  Offset world, {
  double slop = 4,
  CullResult? scratch,
}) {
  final out = scratch ?? CullResult();
  document.scene.queryRect(
    world.dx - _cullPad,
    world.dy - _cullPad,
    world.dx + _cullPad,
    world.dy + _cullPad,
    out,
  );

  final candidates = <int>[];
  for (final slot in out.slots) {
    if (document.strokeIfAlive(slot) != null) candidates.add(slot);
  }
  candidates.sort(
    (a, b) =>
        document.strokeAt(b).zIndex.compareTo(document.strokeAt(a).zIndex),
  );

  for (final slot in candidates) {
    final stroke = document.strokeAt(slot);
    final tolerance = stroke.width / 2 + slop;
    if (_withinTolerance(stroke.points, world.dx, world.dy, tolerance)) {
      return stroke.id;
    }
  }
  return null;
}

bool _withinTolerance(
  Float32List points,
  double px,
  double py,
  double tolerance,
) {
  final toleranceSq = tolerance * tolerance;
  if (points.length < 4) {
    if (points.length < 2) return false;
    return _distanceSq(px, py, points[0], points[1]) <= toleranceSq;
  }
  for (var i = 0; i + 3 < points.length; i += 2) {
    final d = _distanceSqToSegment(
      px,
      py,
      points[i],
      points[i + 1],
      points[i + 2],
      points[i + 3],
    );
    if (d <= toleranceSq) return true;
  }
  return false;
}

double _distanceSq(double px, double py, double ax, double ay) {
  final dx = px - ax;
  final dy = py - ay;
  return dx * dx + dy * dy;
}

double _distanceSqToSegment(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax;
  final dy = by - ay;
  final lengthSq = dx * dx + dy * dy;
  if (lengthSq == 0) return _distanceSq(px, py, ax, ay);
  final t = (((px - ax) * dx + (py - ay) * dy) / lengthSq).clamp(0.0, 1.0);
  return _distanceSq(px, py, ax + t * dx, ay + t * dy);
}
