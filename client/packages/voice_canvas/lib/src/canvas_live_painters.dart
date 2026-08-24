// SPDX-License-Identifier: Apache-2.0
/// The canvas's ephemeral paint layers: this device's own in-progress
/// stroke, everyone else's in-flight strokes, and everyone's live pointers.
///
/// Split out of `canvas_painters.dart` once the elevation-shadow and
/// remote-draft work pushed it toward the 500-line hard limit a second time:
/// none of these four classes touches [StrokePainter]'s own private state,
/// so a plain sibling library is enough - unlike `canvas_painters_shapes.dart`,
/// which needs `part of` for exactly that access. Re-exported from
/// `canvas_painters.dart` so nothing importing that file has to change.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'canvas_cursors.dart';
import 'canvas_document.dart';
import 'canvas_stroke_drafts.dart';
import 'cursor_label_cache.dart';

export 'cursor_label_contrast.dart' show cursorLabelColorFor;

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
/// `CanvasStroke.width` carries, so it must be scaled by the live camera zoom
/// here or the preview disagrees with the committed-ink painter the moment
/// zoom is not 1.
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
/// [DraftPainter] already gives for keeping a drawer's own preview off the
/// committed-ink layer's repaint: a remote pointer moving mid-stroke must
/// not force the whole committed-ink layer to repaint, and vice versa.
/// Colours are drawn at 70% opacity - lighter than committed ink - so an
/// in-flight ghost never reads as though it has already landed.
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
    this.glide = Duration.zero,
    this.now = DateTime.now,
    Listenable? glideTick,
  }) : super(
          repaint: Listenable.merge([
            cursors,
            document,
            if (glideTick != null) glideTick,
          ]),
        );

  final CanvasCursors cursors;
  final CanvasDocument document;

  /// How long a cursor glides to a newly-reported position. Zero (the
  /// default, and what a reduce-motion caller passes) draws each frame at
  /// its target exactly as before; anything longer needs [glideTick] wired
  /// to something that fires while a glide is in flight, since neither
  /// [cursors] nor [document] notifies between frames.
  final Duration glide;

  /// The clock a glide is read against, injectable for a test the same
  /// plain-value way [colors] and [labelFontFamily] already are - this
  /// package deliberately depends on Flutter alone, so no `clock` package.
  final DateTime Function() now;

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

  late final CursorLabelCache _labels = CursorLabelCache(
    fontFamily: labelFontFamily,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;
    final camera = document.camera;
    final paintedAt = now();
    final all = cursors.all;
    for (final cursor in all) {
      final world = cursor.positionAt(paintedAt, glide);
      final at = Offset(
        (world.dx - camera.x) * camera.zoom,
        (world.dy - camera.y) * camera.zoom,
      );
      if (at.dx < -_cullMargin ||
          at.dy < -_cullMargin ||
          at.dx > size.width + _cullMargin ||
          at.dy > size.height + _cullMargin) {
        continue;
      }
      final color = colors[cursor.colorIndex % colors.length];
      _paintGlyph(canvas, at, color);
      _paintLabel(canvas, at, cursor.id, cursor.label, color);
    }
    // Reconcile every frame, since a size check misses a departed cursor whose slot an off-screen (uncached) one took.
    _labels.retain({for (final c in all) c.id});
  }

  /// Frees the label cache; a [CustomPainter] has no teardown hook of its own,
  /// so the owning surface calls this from its own `dispose`.
  void disposeLabels() => _labels.dispose();

  @visibleForTesting
  int get debugLabelCacheSize => _labels.size;

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

  void _paintLabel(
    Canvas canvas,
    Offset at,
    String id,
    String label,
    Color color,
  ) {
    if (label.isEmpty) return;
    final painter = _labels.painterFor(id, label, color);
    final origin = Offset(at.dx + 14, at.dy + 12);
    final chip = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        origin.dx - 4,
        origin.dy - 2,
        painter.width + 8,
        painter.height + 4,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(chip, Paint()..color = color);
    painter.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(CursorPainter oldDelegate) => false;
}
