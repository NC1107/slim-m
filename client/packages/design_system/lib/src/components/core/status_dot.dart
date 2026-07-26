// SPDX-License-Identifier: Apache-2.0
/// A presence indicator: five states, each with its own colour and its own
/// silhouette.
///
/// Colour is never the only cue here. The traffic-light convention is kept
/// because it is the one users already know, but a colour-blind viewer and a
/// screenshot in a bug report both need the state to survive without hue, so
/// every state also gets a distinct shape.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_tokens.dart';

/// [hidden] is "appearing offline": a deliberate privacy choice, not a real
/// disconnect. It has no colour of its own in [AppStatusColors] and reuses
/// [AppStatusColors.offline] on purpose; only the shape tells the two apart.
enum AppPresence { online, away, dnd, offline, hidden }

/// The silhouette each [AppPresence] renders as, independent of colour.
enum AppStatusShape {
  filledDisc,
  triangle,
  notchedSquare,
  hollowRing,
  slashedRing
}

/// A small presence dot, drawn with both a colour and a shape so the state
/// still reads once colour is taken away.
class AppStatusDot extends StatelessWidget {
  const AppStatusDot({
    super.key,
    required this.status,
    this.size = _defaultSize,
    this.backgroundColor,
  });

  final AppPresence status;

  /// Diameter. Defaults to 10, the source design's own default for a
  /// free-standing dot; there is no size token this granular, since a dot's
  /// context (a row, an avatar corner) usually dictates it instead.
  final double size;

  /// What the dot sits on. [AppStatusShape.notchedSquare] and
  /// [AppStatusShape.slashedRing] both punch a mark out of a filled shape in
  /// this colour, so it must match the real backdrop or the mark shows a
  /// seam. Defaults to [AppTokens.surfaceBase].
  final Color? backgroundColor;

  static const double _defaultSize = 10;

  /// The shape for each state, kept as data rather than inlined in [build] so
  /// a test can assert all five stay distinguishable without rendering
  /// pixels.
  static const Map<AppPresence, AppStatusShape> shapeOf = {
    AppPresence.online: AppStatusShape.filledDisc,
    AppPresence.away: AppStatusShape.triangle,
    AppPresence.dnd: AppStatusShape.notchedSquare,
    AppPresence.offline: AppStatusShape.hollowRing,
    AppPresence.hidden: AppStatusShape.slashedRing,
  };

  static const Map<AppPresence, String> _labelOf = {
    AppPresence.online: 'Online',
    AppPresence.away: 'Away',
    AppPresence.dnd: 'Do not disturb',
    AppPresence.offline: 'Offline',
    AppPresence.hidden: 'Appearing offline',
  };

  Color _colorOf(AppStatusColors colors) => switch (status) {
        AppPresence.online => colors.online,
        AppPresence.away => colors.away,
        AppPresence.dnd => colors.dnd,
        AppPresence.offline => colors.offline,
        // No dedicated token: hidden is a privacy choice layered on top of
        // "offline", not a sixth colour, so it reuses offline's.
        AppPresence.hidden => colors.offline,
      };

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Semantics(
      label: _labelOf[status],
      child: CustomPaint(
        size: Size.square(size),
        painter: AppStatusDotPainter(
          shape: shapeOf[status]!,
          color: _colorOf(tokens.status),
          backgroundColor: backgroundColor ?? tokens.surfaceBase,
        ),
      ),
    );
  }
}

/// Draws one of the five [AppStatusShape]s inside a [size]-by-[size] box.
///
/// A public class, not a private `_Painter`, for the same reason
/// [AppStatusDot.shapeOf] is public data: a widget test can reach in and
/// assert `shape` directly instead of inferring it from pixels.
class AppStatusDotPainter extends CustomPainter {
  const AppStatusDotPainter({
    required this.shape,
    required this.color,
    required this.backgroundColor,
  });

  final AppStatusShape shape;
  final Color color;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (shape) {
      case AppStatusShape.filledDisc:
        canvas.drawCircle(center, w / 2, fill);

      case AppStatusShape.triangle:
        final path = Path()
          ..moveTo(w * 0.5, 0)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
        canvas.drawPath(path, fill);

      case AppStatusShape.notchedSquare:
        // A fixed 3px corner: the source hardcodes this regardless of dot
        // size, and no [AppRadii] step is this small (the smallest, 6, reads
        // as a full pill at status-dot sizes).
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Offset.zero & size, const Radius.circular(3)),
            fill);
        final barHeight = math.max(2.0, h * 0.18);
        canvas.drawRect(
          Rect.fromCenter(center: center, width: w * 0.62, height: barHeight),
          Paint()
            ..color = backgroundColor
            ..style = PaintingStyle.fill,
        );

      case AppStatusShape.hollowRing:
        _drawRing(canvas, center, w, h, color);

      case AppStatusShape.slashedRing:
        _drawRing(canvas, center, w, h, color);
        // A flat, non-scaling 2px bar, matching the source exactly; the ring
        // it crosses does scale, since it alone is what has to stay visible
        // at very small sizes.
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(-math.pi / 4);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: w + 2, height: 2),
          Paint()..color = color,
        );
        canvas.restore();
    }
  }

  void _drawRing(
      Canvas canvas, Offset center, double w, double h, Color ringColor) {
    // Border-box sizing: the ring's outer edge sits on the box edge and the
    // stroke eats inward, so the stroked path radius is the outer radius
    // minus half the stroke.
    final strokeWidth = math.max(2.0, w * 0.26);
    canvas.drawCircle(
      center,
      w / 2 - strokeWidth / 2,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant AppStatusDotPainter oldDelegate) {
    return oldDelegate.shape != shape ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
