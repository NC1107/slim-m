// SPDX-License-Identifier: Apache-2.0
/// Reading a widget's real, laid-out position and size straight from its
/// `RenderBox`, for the question a rasterised screenshot cannot answer
/// honestly: is a widget actually where the pixels suggest it is not.
///
/// `ui_snapshot_support.dart`'s own doc comment names two ways the offscreen
/// rasteriser these harnesses use lies about a *picture* (a shadow's blur, a
/// hairline's continuity) without lying about geometry at all - `getRect`
/// walks the true `RenderBox` tree Flutter actually laid out, unaffected by
/// either. A reviewer who suspects a screenshot rather than trusting it
/// should reach for these helpers instead of a bespoke throwaway test: one
/// review pass already had to hand-write exactly this shape once, reading
/// `DockHeightReporter`'s own `RenderBox` position against the test
/// viewport, before this file existed to make that a few lines.
///
/// `screen_safe_area_test.dart`, `composer_safe_area_test.dart`,
/// `rail_safe_area_test.dart` and `canvas_safe_area_shell_test.dart` each
/// already hand-rolled a version of the same `tester.getRect(...).bottom
/// <=/>=/closeTo(...)` shape before this file existed; they are not
/// converted here; a mechanical rename buys nothing an existing, passing
/// test does not already have, and this file's job is to stop a *sixth*
/// hand-rolled copy, not to rewrite the first five.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which side of a rect a gap is measured from.
enum GeometryEdge { top, bottom, left, right }

/// The test viewport's own logical rect, `Offset.zero & size` from the
/// `WidgetTester`'s configured view - what every gap helper below measures
/// against when no [GapFrom.from] widget is given. Divides by
/// `devicePixelRatio` because `tester.view.physicalSize` is in physical
/// pixels and every fixture in this suite that sets a custom size (the
/// safe-area tests above) sets both independently, e.g. `physicalSize =
/// size * dpr`.
Rect viewportRect(WidgetTester tester) {
  final view = tester.view;
  return Offset.zero & (view.physicalSize / view.devicePixelRatio);
}

/// The visible gap between [finder]'s real, rendered [edge] and the
/// matching edge of [from]'s own rect - or, with no [from], the test
/// viewport itself ([viewportRect]). Positive means clear of that edge by
/// that many logical pixels; negative means [finder] has run past it.
///
/// Both rects come from `tester.getRect`, which reads the real, laid-out
/// `RenderBox` - the same value a real screen paints, never estimated from
/// a widget's own requested `padding`/`EdgeInsets` (which a wrapping
/// `SafeArea`, `Align`, or `Expanded` can always change) and never distorted
/// by a shadow or hairline the offscreen rasteriser paints wrong.
double edgeGap(
  WidgetTester tester,
  Finder finder,
  GeometryEdge edge, {
  Finder? from,
}) {
  final rect = tester.getRect(finder);
  final bounds = from != null ? tester.getRect(from) : viewportRect(tester);
  switch (edge) {
    case GeometryEdge.top:
      return rect.top - bounds.top;
    case GeometryEdge.bottom:
      return bounds.bottom - rect.bottom;
    case GeometryEdge.left:
      return rect.left - bounds.left;
    case GeometryEdge.right:
      return bounds.right - rect.right;
  }
}

/// Asserts [edgeGap] equals [expected] within [tolerance] (default half a
/// logical pixel, the tolerance every hand-rolled `closeTo` check this file
/// replaces already used) - the "is this padding actually reaching the
/// screen" question a design spec states as an exact number.
void expectEdgeGap(
  WidgetTester tester,
  Finder finder,
  GeometryEdge edge,
  double expected, {
  Finder? from,
  double tolerance = 0.5,
  String? reason,
}) {
  expect(
    edgeGap(tester, finder, edge, from: from),
    closeTo(expected, tolerance),
    reason: reason,
  );
}

/// Asserts [finder] is clear of [from]'s (or the viewport's) [edge] by at
/// least [minimum] (default 0: merely not past it) - the "must not run
/// under X" shape `screen_safe_area_test.dart`'s own `_expectClearOfIndicator`
/// hand-rolled before this file existed, generalised past "the home
/// indicator" to any edge and any bound.
void expectClearOfEdge(
  WidgetTester tester,
  Finder finder,
  GeometryEdge edge, {
  Finder? from,
  double minimum = 0,
  String? reason,
}) {
  expect(
    edgeGap(tester, finder, edge, from: from),
    greaterThanOrEqualTo(minimum),
    reason: reason,
  );
}
