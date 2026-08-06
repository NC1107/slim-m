// SPDX-License-Identifier: Apache-2.0
/// [canvasStrokeInputFrom]'s dispatch: a wire object's `kind` decides which
/// of `points`, `attachment`, `text` or `shape` this client reads out of an
/// otherwise opaque `props`, and an unparseable or unrecognised one answers
/// null rather than guessing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/screens/canvas/canvas_sync.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

api.CanvasObject _object({
  required String kind,
  Map<String, dynamic> props = const {},
}) => api.CanvasObject(
  id: 'obj-1',
  kind: kind,
  zIndex: 1,
  x: 10,
  y: 20,
  w: 100,
  h: 60,
  props: props,
  authorId: 'alice',
  seq: 1,
  createdAt: 0,
);

void main() {
  test('a note carries its own kind and text through', () {
    final input = canvasStrokeInputFrom(
      _object(kind: 'note', props: {'text': 'buy milk'}),
    );
    expect(input, isNotNull);
    expect(input!.kind, CanvasObjectKind.note);
    expect(input.text, 'buy milk');
    expect(input.colorKey, 'note');
  });

  test('a note with no text, or a non-string one, does not parse', () {
    expect(canvasStrokeInputFrom(_object(kind: 'note')), isNull);
    expect(
      canvasStrokeInputFrom(_object(kind: 'note', props: {'text': 7})),
      isNull,
    );
  });

  test('a shape carries its own kind and shapeKind through', () {
    final input = canvasStrokeInputFrom(
      _object(kind: 'shape', props: {'shape': 'ellipse'}),
    );
    expect(input, isNotNull);
    expect(input!.kind, CanvasObjectKind.shape);
    expect(input.shapeKind, CanvasShapeKind.ellipse);
    expect(input.colorKey, 'shape');
  });

  test('a shape naming an unrecognised primitive does not parse', () {
    expect(
      canvasStrokeInputFrom(_object(kind: 'shape', props: {'shape': 'star'})),
      isNull,
    );
    expect(canvasStrokeInputFrom(_object(kind: 'shape')), isNull);
  });

  test('every wire shape kind round-trips through canvasShapeKindToWire', () {
    for (final kind in CanvasShapeKind.values) {
      expect(canvasShapeKindFromWire(canvasShapeKindToWire(kind)), kind);
    }
  });

  test('an unrecognised top-level kind is null, not a default stroke', () {
    expect(canvasStrokeInputFrom(_object(kind: 'window')), isNull);
  });
}
