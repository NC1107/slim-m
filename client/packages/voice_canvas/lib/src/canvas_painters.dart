// SPDX-License-Identifier: Apache-2.0
/// The canvas paint layers: the lattice, the committed ink, the stroke still
/// under this device's own pointer, and everyone else's in-flight strokes.
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
import 'canvas_stroke_drafts.dart';

/// A note's and a shape's own paint methods, plus the arrowhead's pure
/// geometry: split out once they pushed this file past the 300-line review
/// budget, the same `part of` shape `canvas_document_selection.dart` and
/// `canvas_ops_controller_reorder.dart` already use for a class that grew a
/// second cohesive group of methods rather than a second class.
part 'canvas_painters_shapes.dart';

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
  StrokePainter({
    required this.document,
    required this.ink,
    this.noteColor,
    this.shapeColor,
    this.textInk = const Color(0xFF1A1A1A),
    this.textFontFamily,
    this.placeholderFill = const Color(0xFFB9C0C8),
    this.placeholderIcon = const Color(0xFF6C757E),
    this.elevationShadow = const [],
  }) : super(repaint: Listenable.merge([document, document.elevatedObjectId]));

  final CanvasDocument document;

  /// A pen stroke's own colour, and the fallback for [noteColor] and
  /// [shapeColor] when the caller has no opinion about either - the same
  /// "cheap to omit" shape [CanvasSurface.cursorColors] already uses.
  final Color ink;
  final Color? noteColor;
  final Color? shapeColor;

  /// A note's own text colour. Deliberately not derived from [noteColor]:
  /// the note's fill is a translucent tint of its own accent hue, and text
  /// legible against every theme needs a colour of its own rather than
  /// riding whatever the accent happens to be.
  final Color textInk;
  final String? textFontFamily;

  /// The muted fill and glyph stroke for an image whose bytes could not be
  /// fetched or decoded. Default to plain neutral greys so a caller with no
  /// opinion (a test, a benchmark) still gets a visible placeholder; the
  /// app layer overrides both with its own design tokens.
  final Color placeholderFill;
  final Color placeholderIcon;

  /// The shadow drawn under whichever image `document.elevatedObjectId`
  /// currently names - a plain `BoxShadow` list rather than a design-system
  /// token, this package's usual "no design-system dependency" convention.
  /// Empty draws no elevation at all, the same "pay nothing for it unwired"
  /// choice `CanvasSurface.selectionOutline` already makes.
  final List<BoxShadow> elevationShadow;

  @override
  void paint(Canvas canvas, Size size) {
    final camera = document.camera;
    final elevated = document.elevatedObjectId.value;
    final paint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    for (final slot in document.paintOrder) {
      final stroke = document.strokeAt(slot);
      final isElevated = stroke.id == elevated;
      switch (stroke.kind) {
        case CanvasObjectKind.image:
          _paintImage(canvas, stroke, camera, elevated: isElevated);
          continue;
        case CanvasObjectKind.note:
          _paintNote(
            canvas,
            stroke,
            camera,
            noteColor ?? ink,
            elevated: isElevated,
          );
          continue;
        case CanvasObjectKind.shape:
          _paintShape(
            canvas,
            stroke,
            camera,
            shapeColor ?? ink,
            elevated: isElevated,
          );
          continue;
        case CanvasObjectKind.stroke:
          break;
      }
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

  /// A live bitmap paints normally; a load that failed for good draws the
  /// placeholder, never silence, so a missing image reads as a stated fact
  /// rather than a blank the eye has to guess at. Anything still in flight
  /// (the ordinary case just after a fetch or catch-up) draws nothing yet,
  /// and the object reappears the moment [CanvasDocument.setImageBitmap]
  /// lands and repaints.
  void _paintImage(
    Canvas canvas,
    CanvasStroke stroke,
    Camera camera, {
    required bool elevated,
  }) {
    final dst = Rect.fromLTWH(
      (stroke.x - camera.x) * camera.zoom,
      (stroke.y - camera.y) * camera.zoom,
      stroke.w * camera.zoom,
      stroke.h * camera.zoom,
    );
    if (elevated) _paintElevation(canvas, dst);
    final bitmap = stroke.image;
    if (bitmap == null) {
      if (stroke.imageLoadFailed) _paintImagePlaceholder(canvas, dst);
      return;
    }
    final src = Rect.fromLTWH(
      0,
      0,
      bitmap.width.toDouble(),
      bitmap.height.toDouble(),
    );
    canvas.drawImageRect(
        bitmap, src, dst, Paint()..filterQuality = FilterQuality.medium);
  }

  /// Drawn first, since a shadow always sits behind whatever casts it -
  /// before the bitmap or the placeholder, both of which paint over it.
  /// Applies regardless of which of those two the image is currently
  /// showing, so a drag started before a decode lands still reads as lifted.
  void _paintElevation(Canvas canvas, Rect box) {
    for (final shadow in elevationShadow) {
      canvas.drawRect(
        box.shift(shadow.offset).inflate(shadow.spreadRadius),
        shadow.toPaint(),
      );
    }
  }

  /// A muted box plus a broken-picture glyph (a small square with a
  /// diagonal tear), never colour alone: the same "never one channel alone"
  /// rule this project's own presence indicators already follow, here shape
  /// against a muted fill rather than colour against a status dot.
  void _paintImagePlaceholder(Canvas canvas, Rect box) {
    final fill = Paint()..color = placeholderFill;
    final line = Paint()
      ..color = placeholderIcon
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rounded = RRect.fromRectAndRadius(box, const Radius.circular(4));
    canvas.drawRRect(rounded, fill);
    canvas.drawRRect(rounded.deflate(0.75), line);

    final glyphSize = math.min(box.width, box.height) * 0.32;
    if (glyphSize < 6) return;
    final glyph = Rect.fromCenter(
      center: box.center,
      width: glyphSize,
      height: glyphSize,
    );
    canvas.drawRect(glyph, line);
    canvas.drawLine(glyph.topLeft, glyph.bottomRight, line);
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

/// Other participants' in-flight strokes, in world coordinates.
///
/// Its own layer and its own listening `repaint`, the same reasoning
/// [DraftPainter] already gives for keeping a drawer's own preview off
/// [StrokePainter]'s repaint: a remote pointer moving mid-stroke must not
/// force the whole committed-ink layer to repaint, and vice versa. Colours
/// are drawn at 70% opacity - lighter than [StrokePainter]'s committed ink -
/// so an in-flight ghost never reads as though it has already landed.
class RemoteDraftPainter extends CustomPainter {
  RemoteDraftPainter({
    required this.drafts,
    required this.document,
    required this.colors,
  }) : super(repaint: Listenable.merge([drafts, document]));

  final RemoteStrokeDrafts drafts;
  final CanvasDocument document;

  /// The caller's own closed cursor-colour set, indexed by
  /// [CanvasStrokeDraft.colorIndex] - the same palette [CursorPainter]
  /// draws from, so a participant's in-flight ink and their cursor read as
  /// the same person.
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;
    final camera = document.camera;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3 * camera.zoom
      ..isAntiAlias = true;
    for (final draft in drafts.all) {
      final points = draft.points;
      if (points.length < 4) continue;
      paint.color =
          colors[draft.colorIndex % colors.length].withValues(alpha: 0.7);
      final path = Path()
        ..moveTo(
          (points[0] - camera.x) * camera.zoom,
          (points[1] - camera.y) * camera.zoom,
        );
      for (var i = 2; i < points.length; i += 2) {
        path.lineTo(
          (points[i] - camera.x) * camera.zoom,
          (points[i + 1] - camera.y) * camera.zoom,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(RemoteDraftPainter oldDelegate) => false;
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
    this.labelFontFamily,
  }) : super(repaint: Listenable.merge([cursors, document]));

  final CanvasCursors cursors;
  final CanvasDocument document;

  /// The caller's closed cursor-colour set, indexed by
  /// [CanvasCursor.colorIndex]. This package carries no palette of its own,
  /// the same convention every other painter here follows.
  final List<Color> colors;

  /// The app's own type family for the name chip, the same plain-value
  /// convention [colors] already follows: this package has no font of its
  /// own to fall back on, and leaving this null draws Flutter's platform
  /// default rather than the product's own IBM Plex Sans.
  final String? labelFontFamily;

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

  /// A white rim behind the fill, not a second identical fill: the same path
  /// drawn twice with no stroke and no inset (the shape this replaces) paints
  /// the second pass directly over the first, so the white never actually
  /// shows - a cursor in a hue close to whatever sits behind it (another
  /// participant's ink, a similarly-toned object) had no contrast edge at all.
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
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  void _paintLabel(Canvas canvas, Offset at, String label, Color color) {
    if (label.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: labelFontFamily,
          fontSize: 11,
          color: const Color(0xFFFFFFFF),
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
