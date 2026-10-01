// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Measures what a finger can actually press, not how big a control is drawn.
///
/// Not a `_test.dart` file, so `flutter test` does not run it.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const double touchMin = 44;

bool _hits(WidgetTester tester, Offset point, RenderObject control) {
  final path = tester.hitTestOnBinding(point).path;
  return path.any((entry) {
    for (
      RenderObject? node = entry.target is RenderObject
          ? entry.target as RenderObject
          : null;
      node != null;
      node = node.parent
    ) {
      if (identical(node, control)) return true;
    }
    return false;
  });
}

/// Every edge and corner of the [touchMin] square the control sits in, placed
/// by [alignment], reaches it; a box already wider or taller keeps its own.
void expectTouchTarget(
  WidgetTester tester,
  Finder control, {
  Alignment alignment = Alignment.center,
  String? reason,
}) {
  final box = tester.getRect(control);
  final size = Size(
    math.max(box.width, touchMin),
    math.max(box.height, touchMin),
  );
  final area =
      (box.topLeft -
          alignment.alongOffset(
            Offset(size.width - box.width, size.height - box.height),
          )) &
      size;
  final render = tester.renderObject(control);
  const inset = 0.75;
  final probes = <String, Offset>{
    'top left': area.topLeft + const Offset(inset, inset),
    'top right': area.topRight + const Offset(-inset, inset),
    'bottom left': area.bottomLeft + const Offset(inset, -inset),
    'bottom right': area.bottomRight + const Offset(-inset, -inset),
    'centre': area.center,
  };
  probes.forEach((where, point) {
    expect(
      _hits(tester, point, render),
      isTrue,
      reason:
          '${reason ?? control.toString()}: the $where of a '
          '${area.width.toStringAsFixed(0)}x${area.height.toStringAsFixed(0)} '
          'area does not press it (drawn ${box.width.toStringAsFixed(0)}x'
          '${box.height.toStringAsFixed(0)})',
    );
  });
}
