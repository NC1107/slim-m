// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Realistic content for the assembled-pane review: a canvas that reads as
/// something somebody actually drew on, not three placeholder objects.
///
/// Not a `_test.dart` file, so `flutter test` does not try to run it - the
/// same `canvas_pane_harness.dart` shape. Every builder here is pure Dart
/// plus [CanvasDocument]/[CanvasCursors], so a caller decides for itself
/// whether to wrap the result in a call, a set of cursors, or neither.
library;

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

/// The five people this scene puts on the call: the caller themselves plus
/// four remote participants, spread across camera-on, camera-off, muted and
/// speaking so the presence layer's every branch has something to render.
const busyParticipants = <VoiceParticipant>[
  VoiceParticipant(
    identity: 'me',
    name: 'Me',
    isSpeaking: false,
    isMuted: false,
    isLocal: true,
    isScreenSharing: false,
  ),
  VoiceParticipant(
    identity: 'user-avery',
    name: 'Avery',
    isSpeaking: true,
    isMuted: false,
    isLocal: false,
    isScreenSharing: false,
    isCameraOn: true,
  ),
  VoiceParticipant(
    identity: 'user-jordan',
    name: 'Jordan',
    isSpeaking: false,
    isMuted: true,
    isLocal: false,
    isScreenSharing: false,
  ),
  VoiceParticipant(
    identity: 'user-priya',
    name: 'Priya',
    isSpeaking: false,
    isMuted: false,
    isLocal: false,
    isScreenSharing: false,
  ),
  VoiceParticipant(
    identity: 'user-sam',
    name: 'Sam',
    isSpeaking: false,
    isMuted: false,
    isLocal: false,
    isScreenSharing: false,
    isCameraOn: true,
  ),
];

/// [busyParticipants] with Sam sharing their screen too - the scenario the
/// owner actually asked for: a participant's screen as a second, distinct
/// tile from their camera.
final busyParticipantsSharing = [
  for (final p in busyParticipants)
    if (p.identity == 'user-sam')
      VoiceParticipant(
        identity: p.identity,
        name: p.name,
        isSpeaking: p.isSpeaking,
        isMuted: p.isMuted,
        isLocal: p.isLocal,
        isScreenSharing: true,
        isCameraOn: p.isCameraOn,
      )
    else
      p,
];

/// A sixth person, present only by cursor - never on the call - so the
/// roster's own honest union (call roster plus live cursors) has something
/// to prove: someone who is drawing but never joined voice still counts as
/// present.
CanvasCursors buildBusyCursors() {
  final cursors = CanvasCursors();
  cursors.upsert(
    id: 'user-avery',
    x: 260,
    y: 180,
    label: 'Avery',
    colorIndex: 0,
  );
  cursors.upsert(
    id: 'user-robin',
    x: 760,
    y: 520,
    label: 'Robin',
    colorIndex: 3,
  );
  return cursors;
}

CanvasStrokeInput _ink(
  String id,
  int seq,
  double x,
  double y,
  double w,
  double h,
  List<double> points, {
  double width = 4,
}) => CanvasStrokeInput(
  id: id,
  seq: seq,
  zIndex: seq,
  x: x,
  y: y,
  w: w,
  h: h,
  points: points,
  width: width,
  colorKey: 'annotation',
  authorId: 'me',
);

CanvasStrokeInput _shape(
  String id,
  int seq,
  double x,
  double y,
  double w,
  double h,
  CanvasShapeKind kind,
) => CanvasStrokeInput(
  id: id,
  seq: seq,
  zIndex: seq,
  x: x,
  y: y,
  w: w,
  h: h,
  points: const [],
  width: 0,
  colorKey: 'shape',
  kind: CanvasObjectKind.shape,
  shapeKind: kind,
  authorId: 'user-priya',
);

CanvasStrokeInput _note(
  String id,
  int seq,
  double x,
  double y,
  double w,
  double h,
  String text,
) => CanvasStrokeInput(
  id: id,
  seq: seq,
  zIndex: seq,
  x: x,
  y: y,
  w: w,
  h: h,
  points: const [],
  width: 0,
  colorKey: 'note',
  kind: CanvasObjectKind.note,
  text: text,
  authorId: 'user-jordan',
);

CanvasStrokeInput _image(
  String id,
  int seq,
  double x,
  double y,
  double w,
  double h,
) => CanvasStrokeInput(
  id: id,
  seq: seq,
  zIndex: seq,
  x: x,
  y: y,
  w: w,
  h: h,
  points: const [],
  width: 0,
  colorKey: '',
  kind: CanvasObjectKind.image,
  attachmentId: 'sha-$id',
  authorId: 'user-sam',
);

/// A diagram somebody actually made: a boxed cluster with freehand ink
/// inside it, an arrow to a callout note, a divider, two more notes at
/// genuinely different lengths, two shapes, and two images - one hydrated,
/// one failed - spread from world (60, 60) out to about (1400, 820), the
/// same shape `scripts/seed-canvas.py`'s own "one deliberate diagram"
/// reasoning describes. Deliberately overlaps the presence layer's own
/// top-left tile row (world (24, 24), 220x160 per bubble) rather than
/// avoiding it, since a real session has no way to know where bubbles will
/// land before drawing.
CanvasDocument buildBusyDocument({ui.Image? hydratedImage}) {
  final document = CanvasDocument();
  document.applyPlaced(
    _shape('box-cluster', 1, 60, 60, 340, 220, CanvasShapeKind.rectangle),
  );
  document.applyPlaced(
    _ink('freehand-1', 2, 60, 60, 340, 220, const [
      20, 150, //
      80, 40, 160, 120, 240, 30, 320, 140,
    ]),
  );
  document.applyPlaced(
    _shape('arrow-1', 3, 400, 130, 60, 20, CanvasShapeKind.arrow),
  );
  document.applyPlaced(
    _note(
      'note-callout',
      4,
      460,
      70,
      240,
      140,
      'Rough plan: mock the busy scene, compare all three themes, and see '
          'whether the dock ever sits on top of real ink.',
    ),
  );
  document.applyPlaced(
    _shape('ellipse-1', 5, 760, 260, 200, 150, CanvasShapeKind.ellipse),
  );
  document.applyPlaced(
    _shape('divider-1', 6, 60, 440, 900, 3, CanvasShapeKind.line),
  );
  document.applyPlaced(_note('note-short', 7, 60, 480, 200, 110, 'Ship it.'));
  document.applyPlaced(
    _note(
      'note-long',
      8,
      300,
      480,
      220,
      150,
      'Standup notes: this is what a note sized for three lines does with '
          'six lines of real text in it - does it clip mid-word, does it scroll, '
          'or does it just run off the bottom with nothing telling you it did.',
    ),
  );
  document.applyPlaced(
    _ink('scribble-1', 9, 760, 480, 260, 160, const [
      0,
      0,
      40,
      90,
      90,
      20,
      140,
      110,
      190,
      10,
      240,
      100,
    ]),
  );
  document.applyPlaced(_image('image-hydrated', 10, 1060, 480, 200, 150));
  document.applyPlaced(_image('image-failed', 11, 1290, 480, 120, 120));
  document.markImageLoadFailed('image-failed');
  if (hydratedImage != null) {
    document.setImageBitmap('image-hydrated', hydratedImage);
  }
  document.refresh();
  return document;
}

CanvasDocument buildEmptyDocument() => CanvasDocument()..refresh();

/// A synthetic photo-like bitmap - a diagonal gradient, not a solid swatch -
/// so a hydrated image reads as a picture rather than a colour chip. Real
/// `dart:ui` raster work, so a caller must run this inside `tester.runAsync`
/// the same way `writeSnapshot` already has to for `toImage`.
Future<ui.Image> buildGradientImage(
  int width,
  int height,
  Color from,
  Color to,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [from, to]),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}
