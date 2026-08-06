// SPDX-License-Identifier: Apache-2.0
part of 'canvas_painters.dart';

/// [StrokePainter]'s note and shape paint methods. An extension in a `part
/// of` file, not a second class, since both still need [StrokePainter]'s own
/// private fields (`textInk`, `textFontFamily`) and are called from its
/// `paint` method's own switch.
extension _StrokePainterShapes on StrokePainter {
  /// A tinted box with a text body, painted in screen space the same way
  /// `_paintImage` already projects its own box - simpler than the
  /// world-scale `save`/`translate`/`scale` the ink branch uses, and correct
  /// here because the text layout width is computed straight from the
  /// already-projected screen box rather than from a world-space one.
  void _paintNote(
    Canvas canvas,
    CanvasStroke stroke,
    Camera camera,
    Color color, {
    required bool elevated,
  }) {
    final box = Rect.fromLTWH(
      (stroke.x - camera.x) * camera.zoom,
      (stroke.y - camera.y) * camera.zoom,
      stroke.w * camera.zoom,
      stroke.h * camera.zoom,
    );
    if (elevated) _paintElevation(canvas, box);
    final rounded = RRect.fromRectAndRadius(box, const Radius.circular(6));
    canvas.drawRRect(rounded, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawRRect(
      rounded.deflate(0.75),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final text = stroke.text;
    const pad = 8.0;
    if (text == null || text.isEmpty || box.width <= pad * 2) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: textFontFamily,
          fontSize: 12 * camera.zoom,
          color: textInk,
          height: 1.3,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 200,
      ellipsis: '…',
    )..layout(maxWidth: box.width - pad * 2, minWidth: 0);
    canvas.save();
    canvas.clipRect(box.deflate(pad / 2));
    painter.paint(canvas, box.topLeft + const Offset(pad, pad));
    canvas.restore();
  }

  /// A shape's own box, drawn as whichever of [CanvasShapeKind] it names. A
  /// line or an arrow is always the box's own diagonal - see
  /// [CanvasShapeKind]'s own doc for why that is what makes a resize the
  /// whole reshape mechanism, with nothing else to keep in step.
  void _paintShape(
    Canvas canvas,
    CanvasStroke stroke,
    Camera camera,
    Color color, {
    required bool elevated,
  }) {
    final box = Rect.fromLTWH(
      (stroke.x - camera.x) * camera.zoom,
      (stroke.y - camera.y) * camera.zoom,
      stroke.w * camera.zoom,
      stroke.h * camera.zoom,
    );
    if (elevated) _paintElevation(canvas, box);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = true;
    switch (stroke.shapeKind) {
      case CanvasShapeKind.ellipse:
        canvas.drawOval(box, paint);
      case CanvasShapeKind.line:
        canvas.drawLine(box.topLeft, box.bottomRight, paint);
      case CanvasShapeKind.arrow:
        canvas.drawLine(box.topLeft, box.bottomRight, paint);
        _paintArrowhead(canvas, box.topLeft, box.bottomRight, paint);
      case CanvasShapeKind.rectangle:
      case null:
        canvas.drawRect(box, paint);
    }
  }

  void _paintArrowhead(Canvas canvas, Offset from, Offset to, Paint paint) {
    final (left, right) = arrowheadWings(from, to);
    canvas.drawLine(to, left, paint);
    canvas.drawLine(to, right, paint);
  }
}

/// The two short segments an arrowhead draws back from [to], pure geometry
/// so it can be tested without a canvas: a `from`-to-`to` line with nothing
/// at its far end does not read as an arrow, and this is the one thing
/// [CanvasShapeKind.arrow] adds over [CanvasShapeKind.line].
(Offset, Offset) arrowheadWings(
  Offset from,
  Offset to, {
  double headLength = 10,
  double headAngle = 0.5,
}) {
  final direction = to - from;
  if (direction.distance == 0) return (to, to);
  final angle = math.atan2(direction.dy, direction.dx);
  final left = to -
      Offset(math.cos(angle - headAngle), math.sin(angle - headAngle)) *
          headLength;
  final right = to -
      Offset(math.cos(angle + headAngle), math.sin(angle + headAngle)) *
          headLength;
  return (left, right);
}
