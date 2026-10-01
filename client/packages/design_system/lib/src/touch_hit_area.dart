// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A hit area padded out to the touch floor without moving anything drawn.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'app_metrics.dart';
import 'touch_targets.dart';

/// Lets a finger press [child] from anywhere in a [AppSizes.rowTouch] square
/// around it, while [child] keeps the size it is drawn at.
///
/// For a control whose drawn size is the design (an avatar, a name, a colour
/// swatch, a quote line) and so cannot grow into a 44pt row. The extra area
/// can overlap a neighbour's; the neighbour later in paint order wins, which
/// is how Material pads its own small targets.
///
/// An ancestor only passes a press down while it contains it, so the extra
/// area has to lie inside a parent that has room for it. [alignment] says
/// where [child] sits in the padded area and so which side the extra goes to:
/// the default splits it evenly, [Alignment.topLeft] sends it right and down
/// for a control that is first in its parent's box.
///
/// Off, and a plain pass-through, wherever [AppTouchTargets.of] says the
/// window is not at touch density, so a pointer layout is not given invisible
/// hit areas that steal clicks from the controls beside it.
class AppTouchHitArea extends SingleChildRenderObjectWidget {
  const AppTouchHitArea({
    super.key,
    this.touch,
    this.alignment = Alignment.center,
    super.child,
  });

  /// Left null it follows [AppTouchTargets.of].
  final bool? touch;

  /// Where [child] sits inside the padded area.
  final Alignment alignment;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTouchHitArea(_minFor(context), alignment);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderProxyBox renderObject,
  ) {
    (renderObject as _RenderTouchHitArea)
      ..minSize = _minFor(context)
      ..alignment = alignment;
  }

  double _minFor(BuildContext context) =>
      (touch ?? AppTouchTargets.of(context)) ? AppSizes.rowTouch : 0;
}

class _RenderTouchHitArea extends RenderProxyBox {
  _RenderTouchHitArea(this._minSize, this.alignment);

  double _minSize;
  Alignment alignment;

  set minSize(double value) => _minSize = value;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (super.hitTest(result, position: position)) return true;
    final child = this.child;
    if (child == null || _minSize == 0) return false;
    final reachSize = Size(
      math.max(size.width, _minSize),
      math.max(size.height, _minSize),
    );
    final origin = -alignment.alongOffset(
      Offset(reachSize.width - size.width, reachSize.height - size.height),
    );
    if (!(origin & reachSize).contains(position)) return false;
    final centre = size.center(Offset.zero);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(centre),
      position: centre,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }
}
