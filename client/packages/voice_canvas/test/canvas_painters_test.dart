// SPDX-License-Identifier: Apache-2.0
/// The draft stroke under the pointer must paint at the width and place it
/// will keep once committed, or a stroke visibly changes size at pointer-up.
///
/// A stub [Canvas] tracks the actual affine transform `save`/`translate`/
/// `scale`/`restore` build up, the way the real engine would, so what is
/// asserted here is the on-screen result each painter reaches rather than the
/// constructor arguments either was built with.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/src/canvas_document.dart';
import 'package:slimm_voice_canvas/src/canvas_painters.dart';

const _ink = Color(0xFFE86A5C);

class _Transform {
  const _Transform(this.tx, this.ty, this.scale);

  final double tx;
  final double ty;
  final double scale;

  Rect apply(Rect r) => Rect.fromLTRB(
        tx + scale * r.left,
        ty + scale * r.top,
        tx + scale * r.right,
        ty + scale * r.bottom,
      );
}

/// Records what each painter actually reaches at `drawPath`, not what its
/// constructor was handed: the device-space stroke width (raw `strokeWidth`
/// times whatever `scale` was active) and the device-space path bounds.
class _RecordingCanvas implements Canvas {
  final List<double> deviceStrokeWidths = <double>[];
  final List<Rect> deviceBounds = <Rect>[];
  final List<_Transform> _stack = <_Transform>[const _Transform(0, 0, 1)];

  /// Every rounded-rect draw: an image placeholder's or a note's fill and
  /// its border, two calls per object and none for anything else this
  /// painter draws.
  int roundedRectCalls = 0;

  /// A shape's own draw calls, one kind of primitive at a time: a rectangle
  /// or an ellipse each draw once, a line draws once via [drawLine], and an
  /// arrow draws the same line plus two more via [drawLine] for its head.
  int rectCalls = 0;
  int ovalCalls = 0;
  int lineCalls = 0;

  /// Every plain-rect draw carrying a blur, which is what an elevation
  /// shadow's `Paint` looks like once `BoxShadow.toPaint()` builds it -
  /// nothing else this painter draws sets a `maskFilter` at all, so
  /// [drawRect] routes here instead of [rectCalls] whenever one is set.
  int shadowRectCalls = 0;

  _Transform get _current => _stack.last;

  @override
  void save() => _stack.add(_current);

  @override
  void restore() {
    if (_stack.length > 1) _stack.removeLast();
  }

  @override
  void translate(double dx, double dy) {
    final c = _current;
    _stack[_stack.length - 1] =
        _Transform(c.tx + c.scale * dx, c.ty + c.scale * dy, c.scale);
  }

  @override
  void scale(double sx, [double? sy]) {
    final c = _current;
    _stack[_stack.length - 1] = _Transform(c.tx, c.ty, c.scale * sx);
  }

  @override
  void drawPath(Path path, Paint paint) {
    deviceStrokeWidths.add(paint.strokeWidth * _current.scale);
    deviceBounds.add(_current.apply(path.getBounds()));
  }

  @override
  void drawRRect(RRect rrect, Paint paint) => roundedRectCalls++;

  @override
  void drawRect(Rect rect, Paint paint) {
    if (paint.maskFilter != null) {
      shadowRectCalls++;
    } else {
      rectCalls++;
    }
  }

  @override
  void drawOval(Rect rect, Paint paint) => ovalCalls++;

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lineCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

CanvasStrokeInput _noteAt({String text = 'hello'}) => CanvasStrokeInput(
      id: 'note',
      seq: 1,
      zIndex: 1,
      x: 0,
      y: 0,
      w: 120,
      h: 80,
      points: const [],
      width: 0,
      colorKey: 'note',
      kind: CanvasObjectKind.note,
      text: text,
    );

CanvasStrokeInput _shapeAt(CanvasShapeKind shapeKind) => CanvasStrokeInput(
      id: 'shape',
      seq: 1,
      zIndex: 1,
      x: 0,
      y: 0,
      w: 100,
      h: 60,
      points: const [],
      width: 0,
      colorKey: 'shape',
      kind: CanvasObjectKind.shape,
      shapeKind: shapeKind,
    );

/// A document holding one live image object with no bitmap yet, either
/// still waiting on a decode or one that failed for good.
CanvasDocument _documentWithImage({required bool loadFailed}) {
  final document = CanvasDocument();
  document.setViewport(const Size(400, 400));
  document.applyPlaced(
    const CanvasStrokeInput(
      id: 'pic',
      seq: 1,
      zIndex: 1,
      x: 0,
      y: 0,
      w: 100,
      h: 100,
      points: [],
      width: 0,
      colorKey: '',
      kind: CanvasObjectKind.image,
      attachmentId: 'sha-pic',
    ),
  );
  if (loadFailed) document.markImageLoadFailed('pic');
  document.refresh();
  return document;
}

/// A document holding one committed horizontal stroke, camera set last so the
/// placed object is culled in before anything paints.
CanvasDocument _documentWithCommittedStroke(double zoom) {
  final document = CanvasDocument();
  document.setViewport(const Size(400, 400));
  document.applyPlaced(
    const CanvasStrokeInput(
      id: 'committed',
      seq: 1,
      zIndex: 1,
      x: 0,
      y: 50,
      w: 100,
      h: 1,
      points: [0, 0, 100, 0],
      width: 4,
      colorKey: 'ink',
    ),
  );
  document.setCamera(Camera(zoom: zoom));
  return document;
}

DraftStroke _draftAlongTheSameLine() => DraftStroke()
  ..begin(const Offset(0, 175))
  ..extend(const Offset(350, 175));

void main() {
  test(
      'a draft stroke reaches the same on-screen width as the committed '
      'stroke once zoom is not 1', () {
    const zoom = 3.5;
    final document = _documentWithCommittedStroke(zoom);
    addTearDown(document.dispose);

    final committedCanvas = _RecordingCanvas();
    StrokePainter(document: document, ink: _ink)
        .paint(committedCanvas, const Size(400, 400));

    final draft = _draftAlongTheSameLine();
    addTearDown(draft.dispose);
    final draftCanvas = _RecordingCanvas();
    DraftPainter(draft: draft, document: document, ink: _ink, width: 4)
        .paint(draftCanvas, const Size(400, 400));

    expect(committedCanvas.deviceStrokeWidths, [4.0 * zoom]);
    expect(
      draftCanvas.deviceStrokeWidths,
      committedCanvas.deviceStrokeWidths,
      reason: 'the preview must land at the width the committed stroke will '
          'have, or the stroke changes size the instant the pointer lifts',
    );
  });

  test(
      'a draft stroke lands at the same on-screen place and shape as the '
      'committed stroke', () {
    final document = _documentWithCommittedStroke(3.5);
    addTearDown(document.dispose);

    final committedCanvas = _RecordingCanvas();
    StrokePainter(document: document, ink: _ink)
        .paint(committedCanvas, const Size(400, 400));

    final draft = _draftAlongTheSameLine();
    addTearDown(draft.dispose);
    final draftCanvas = _RecordingCanvas();
    DraftPainter(draft: draft, document: document, ink: _ink, width: 4)
        .paint(draftCanvas, const Size(400, 400));

    expect(draftCanvas.deviceBounds, committedCanvas.deviceBounds);
  });

  test('a load that failed for good draws the placeholder, not silence', () {
    final document = _documentWithImage(loadFailed: true);
    addTearDown(document.dispose);

    final canvas = _RecordingCanvas();
    StrokePainter(document: document, ink: _ink).paint(
      canvas,
      const Size(400, 400),
    );

    expect(
      canvas.roundedRectCalls,
      greaterThan(0),
      reason: 'a missing image must draw something, never nothing at all',
    );
  });

  test('a decode still in flight draws nothing yet, not the placeholder', () {
    final document = _documentWithImage(loadFailed: false);
    addTearDown(document.dispose);

    final canvas = _RecordingCanvas();
    StrokePainter(document: document, ink: _ink).paint(
      canvas,
      const Size(400, 400),
    );

    expect(
      canvas.roundedRectCalls,
      0,
      reason: 'the object reappears the moment its own decode lands; '
          'painting a placeholder meanwhile would flash it needlessly',
    );
  });

  test('a note draws its own box, distinct from a plain stroke', () {
    final document = CanvasDocument()..setViewport(const Size(400, 400));
    document.applyPlaced(_noteAt());
    document.refresh();
    addTearDown(document.dispose);

    final canvas = _RecordingCanvas();
    StrokePainter(document: document, ink: _ink).paint(
      canvas,
      const Size(400, 400),
    );

    expect(
      canvas.roundedRectCalls,
      greaterThanOrEqualTo(2),
      reason: 'a note draws a fill and a border, the same two-call shape an '
          'image placeholder already uses',
    );
  });

  const shadow = [
    BoxShadow(color: Color(0x85000000), blurRadius: 64, offset: Offset(0, 24)),
  ];

  test('the elevated image draws its shadow, and an idle one draws none', () {
    final document = _documentWithImage(loadFailed: true)
      ..elevatedObjectId.value = 'pic';
    addTearDown(document.dispose);

    final canvas = _RecordingCanvas();
    StrokePainter(document: document, ink: _ink, elevationShadow: shadow)
        .paint(canvas, const Size(400, 400));

    expect(
      canvas.shadowRectCalls,
      1,
      reason: 'only the object elevatedObjectId names earns a shadow',
    );
  });

  test('an elevated note or shape draws its shadow too', () {
    for (final object in [_noteAt(), _shapeAt(CanvasShapeKind.rectangle)]) {
      final document = CanvasDocument()..setViewport(const Size(400, 400));
      document.applyPlaced(object);
      document.elevatedObjectId.value = object.id;
      document.refresh();

      final canvas = _RecordingCanvas();
      StrokePainter(document: document, ink: _ink, elevationShadow: shadow)
          .paint(canvas, const Size(400, 400));

      expect(canvas.shadowRectCalls, 1, reason: 'kind: ${object.kind}');
      document.dispose();
    }
  });

  test('nothing draws a shadow while no object is elevated', () {
    final document = _documentWithImage(loadFailed: true);
    addTearDown(document.dispose);

    final canvas = _RecordingCanvas();
    StrokePainter(document: document, ink: _ink, elevationShadow: shadow)
        .paint(canvas, const Size(400, 400));

    expect(canvas.shadowRectCalls, 0);
  });

  test('an elevated image draws no shadow when none was wired in', () {
    final document = _documentWithImage(loadFailed: true)
      ..elevatedObjectId.value = 'pic';
    addTearDown(document.dispose);

    final canvas = _RecordingCanvas();
    StrokePainter(document: document, ink: _ink).paint(
      canvas,
      const Size(400, 400),
    );

    expect(
      canvas.shadowRectCalls,
      0,
      reason: 'the default elevationShadow is empty, the same '
          '"pay nothing for it unwired" choice selectionOutline makes',
    );
  });

  test('each shape kind draws through its own primitive', () {
    for (final (kind, assertOn)
        in <(CanvasShapeKind, void Function(_RecordingCanvas))>[
      (CanvasShapeKind.rectangle, (c) => expect(c.rectCalls, 1)),
      (CanvasShapeKind.ellipse, (c) => expect(c.ovalCalls, 1)),
      (CanvasShapeKind.line, (c) => expect(c.lineCalls, 1)),
    ]) {
      final document = CanvasDocument()..setViewport(const Size(400, 400));
      document.applyPlaced(_shapeAt(kind));
      document.refresh();
      final canvas = _RecordingCanvas();
      StrokePainter(document: document, ink: _ink).paint(
        canvas,
        const Size(400, 400),
      );
      assertOn(canvas);
      document.dispose();
    }
  });

  test('an arrow draws its line plus a two-segment head; a line does not', () {
    final line = CanvasDocument()..setViewport(const Size(400, 400));
    line.applyPlaced(_shapeAt(CanvasShapeKind.line));
    line.refresh();
    final lineCanvas = _RecordingCanvas();
    StrokePainter(document: line, ink: _ink).paint(
      lineCanvas,
      const Size(400, 400),
    );
    expect(lineCanvas.lineCalls, 1);
    line.dispose();

    final arrow = CanvasDocument()..setViewport(const Size(400, 400));
    arrow.applyPlaced(_shapeAt(CanvasShapeKind.arrow));
    arrow.refresh();
    final arrowCanvas = _RecordingCanvas();
    StrokePainter(document: arrow, ink: _ink).paint(
      arrowCanvas,
      const Size(400, 400),
    );
    expect(
      arrowCanvas.lineCalls,
      3,
      reason: 'the shaft plus the two head segments arrowheadWings computes',
    );
    arrow.dispose();
  });

  test('arrowheadWings answers (to, to) for a zero-length arrow', () {
    const to = Offset(5, 5);
    expect(arrowheadWings(to, to), (to, to));
  });

  test('arrowheadWings points back from the tip, never past it', () {
    final (left, right) = arrowheadWings(Offset.zero, const Offset(100, 0));
    expect(left.dx, lessThan(100));
    expect(right.dx, lessThan(100));
  });
}
