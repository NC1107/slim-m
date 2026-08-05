// SPDX-License-Identifier: Apache-2.0
/// The three paint layers: the lattice, the committed ink, and the stroke
/// still under the pointer.
///
/// Each takes its own `repaint` listenable and answers `shouldRepaint` false,
/// which is the shape the Phase 5 spike's `benchmark/paint_paths.dart` proved:
/// the painter object is constructed once and a camera move repaints without
/// any widget rebuilding.
///
/// Colours arrive as plain [Color]s from the app layer. This package does not
/// depend on the design system, the same convention every existing painter in
/// the client follows.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'canvas_cursors.dart';
import 'canvas_document.dart';

/// The background lattice, at a spacing quantised to the zoom so the mesh
/// keeps roughly the same density on screen at any scale.
class GridPainter extends CustomPainter {
  GridPainter({required this.document, required this.line})
      : super(repaint: document);

  final CanvasDocument document;
  final Color line;

  static const double _targetScreenSpacing = 64;

  @override
  void paint(Canvas canvas, Size size) {
    final zoom = document.camera.zoom;
    final exponent = (math.log(_targetScreenSpacing / zoom) / math.ln2).round();
    final spacing = math.pow(2, exponent).toDouble();
    final screenSpacing = spacing * zoom;
    if (screenSpacing < 8) return;

    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    final firstX = (document.camera.x / spacing).floorToDouble() * spacing;
    final firstY = (document.camera.y / spacing).floorToDouble() * spacing;
    for (var wx = firstX;
        (wx - document.camera.x) * zoom <= size.width;
        wx += spacing) {
      final sx = (wx - document.camera.x) * zoom;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), paint);
    }
    for (var wy = firstY;
        (wy - document.camera.y) * zoom <= size.height;
        wy += spacing) {
      final sy = (wy - document.camera.y) * zoom;
      canvas.drawLine(Offset(0, sy), Offset(size.width, sy), paint);
    }
  }

  @override
  bool shouldRepaint(GridPainter oldDelegate) => false;
}

/// The committed ink.
class StrokePainter extends CustomPainter {
  StrokePainter({required this.document, required this.ink})
      : super(repaint: document);

  final CanvasDocument document;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final camera = document.camera;
    final paint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    for (final slot in document.paintOrder) {
      final stroke = document.strokeAt(slot);
      canvas.save();
      // Recentering, exactly: a screen-sized translate in Dart doubles keeps Skia's float32 rasteriser away from world coordinates.
      canvas.translate(
        (stroke.x - camera.x) * camera.zoom,
        (stroke.y - camera.y) * camera.zoom,
      );
      canvas.scale(camera.zoom);
      paint.strokeWidth = stroke.width;
      canvas.drawPath(stroke.path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(StrokePainter oldDelegate) => false;
}

/// The stroke currently under the pointer, in screen coordinates.
///
/// Its own layer and its own listenable so pointer-rate repaints never touch
/// the committed ink.
class DraftStroke extends ChangeNotifier {
  final List<Offset> _screenPoints = <Offset>[];

  List<Offset> get points => _screenPoints;
  bool get isEmpty => _screenPoints.isEmpty;

  void begin(Offset point) {
    _screenPoints
      ..clear()
      ..add(point);
    notifyListeners();
  }

  /// Adds a point unless it is within [minGap] device pixels of the last one,
  /// which is the simplification: measured in screen space, so it is
  /// zoom-aware for free.
  void extend(Offset point, {double minGap = 2}) {
    if (_screenPoints.isEmpty) {
      begin(point);
      return;
    }
    if ((point - _screenPoints.last).distance < minGap) return;
    _screenPoints.add(point);
    notifyListeners();
  }

  List<Offset> take() {
    final out = List<Offset>.from(_screenPoints);
    _screenPoints.clear();
    notifyListeners();
    return out;
  }

  void cancel() {
    if (_screenPoints.isEmpty) return;
    _screenPoints.clear();
    notifyListeners();
  }
}

/// Paints [DraftStroke] straight in screen space.
///
/// [width] is the pen's width in world units, the same quantity a committed
/// [CanvasStroke.width] carries, so it must be scaled by the live camera zoom
/// here or the preview disagrees with [StrokePainter] the moment zoom is not 1.
class DraftPainter extends CustomPainter {
  DraftPainter({
    required this.draft,
    required this.document,
    required this.ink,
    required this.width,
  }) : super(repaint: Listenable.merge([draft, document]));

  final DraftStroke draft;
  final CanvasDocument document;
  final Color ink;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final points = draft.points;
    if (points.length < 2) return;
    final paint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width * document.camera.zoom
      ..isAntiAlias = true;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(DraftPainter oldDelegate) => false;
}

/// Other participants' live pointers.
///
/// Its own layer, listening to both [cursors] and [document]: a cursor move
/// repaints with no camera change, and a pan repaints every shown cursor at
/// its new screen position with no cursor having moved in world space.
class CursorPainter extends CustomPainter {
  CursorPainter({
    required this.cursors,
    required this.document,
    required this.colors,
  }) : super(repaint: Listenable.merge([cursors, document]));

  final CanvasCursors cursors;
  final CanvasDocument document;

  /// The caller's closed cursor-colour set, indexed by
  /// [CanvasCursor.colorIndex]. This package carries no palette of its own,
  /// the same convention every other painter here follows.
  final List<Color> colors;

  /// Pixels of screen-space margin past which a cursor is not worth drawing
  /// at all, since its glyph and label would be fully off-canvas anyway.
  static const double _cullMargin = 48;

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;
    final camera = document.camera;
    for (final cursor in cursors.all) {
      final at = Offset(
        (cursor.x - camera.x) * camera.zoom,
        (cursor.y - camera.y) * camera.zoom,
      );
      if (at.dx < -_cullMargin ||
          at.dy < -_cullMargin ||
          at.dx > size.width + _cullMargin ||
          at.dy > size.height + _cullMargin) {
        continue;
      }
      final color = colors[cursor.colorIndex % colors.length];
      _paintGlyph(canvas, at, color);
      _paintLabel(canvas, at, cursor.label, color);
    }
  }

  void _paintGlyph(Canvas canvas, Offset at, Color color) {
    final path = Path()
      ..moveTo(at.dx, at.dy)
      ..lineTo(at.dx, at.dy + 15)
      ..lineTo(at.dx + 4.5, at.dy + 11.5)
      ..lineTo(at.dx + 7, at.dy + 17)
      ..lineTo(at.dx + 9.5, at.dy + 16)
      ..lineTo(at.dx + 7, at.dy + 10.5)
      ..lineTo(at.dx + 11.5, at.dy + 10.5)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  void _paintLabel(Canvas canvas, Offset at, String label, Color color) {
    if (label.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFFFFFFFF),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 160);
    final origin = Offset(at.dx + 14, at.dy + 12);
    final chip = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        origin.dx - 4,
        origin.dy - 2,
        painter.width + 8,
        painter.height + 4,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(chip, Paint()..color = color);
    painter.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(CursorPainter oldDelegate) => false;
}
