// SPDX-License-Identifier: Apache-2.0
/// CP5: a cursor's name chip must be laid out once and reused, not re-shaped on
/// every paint. `CursorPainter` repaints every frame while a cursor glides, but
/// its label text and colour do not change frame to frame - only its position
/// does - so `TextPainter.layout` on each paint was pure waste.
///
/// A rendered frame looks identical whether or not the text was re-laid-out, so
/// these count layouts through [debugCursorLabelLayoutCounts] rather than
/// reading pixels, the same way the client's member-row rebuild test does. They
/// also check the laid-out text itself, so a cache that reuses the wrong entry
/// (drawing stale text) cannot pass on the count alone.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/src/cursor_label_cache.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

class _RecordingCanvas implements Canvas {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

CanvasCursors _oneCursor({String label = 'Ada Lovelace'}) {
  final cursors = CanvasCursors();
  cursors.upsert(id: 'user-ada', x: 0, y: 0, label: label, colorIndex: 0);
  return cursors;
}

CursorPainter _painter(CanvasCursors cursors, CanvasDocument document) =>
    CursorPainter(
      cursors: cursors,
      document: document,
      colors: const [Color(0xFFE0699A)],
    );

void main() {
  test('an unchanged cursor lays its label out once across repeated paints',
      () {
    debugResetCursorLabelLayoutCounts();
    final document = CanvasDocument();
    addTearDown(document.dispose);
    final cursors = _oneCursor();
    addTearDown(cursors.dispose);

    final painter = _painter(cursors, document);
    final canvas = _RecordingCanvas();
    for (var frame = 0; frame < 5; frame++) {
      painter.paint(canvas, const Size(400, 400));
    }
    expect(
      debugCursorLabelLayoutCounts['user-ada'],
      1,
      reason: 'five frames of an unchanged label is one layout',
    );

    // A genuine label change must re-shape the text and draw the new text.
    cursors.upsert(
      id: 'user-ada',
      x: 0,
      y: 0,
      label: 'Ada B. Lovelace',
      colorIndex: 0,
    );
    painter.paint(canvas, const Size(400, 400));
    expect(debugCursorLabelLayoutCounts['user-ada'], 2);
  });

  test(
      'the cache returns the laid-out text it was asked for, never a stale '
      'entry', () {
    final cache = CursorLabelCache();
    const color = Color(0xFF111111);

    final first = cache.painterFor('a', 'Ada', color);
    expect(first.text?.toPlainText(), 'Ada');

    // Same id, new label: the returned painter must carry the new text.
    final second = cache.painterFor('a', 'Bo', color);
    expect(second.text?.toPlainText(), 'Bo');

    // A hit returns the identical painter instance, still holding its text.
    final hit = cache.painterFor('a', 'Bo', color);
    expect(identical(hit, second), isTrue);
    expect(hit.text?.toPlainText(), 'Bo');
  });

  test('the cache rebuilds on a colour change and reuses otherwise', () {
    debugResetCursorLabelLayoutCounts();
    final cache = CursorLabelCache();
    const black = Color(0xFF111111);

    cache.painterFor('a', 'Ada', black);
    cache.painterFor('a', 'Ada', black);
    expect(
      debugCursorLabelLayoutCounts['a'],
      1,
      reason: 'same inputs, one layout',
    );

    cache.painterFor('a', 'Ada', const Color(0xFF222222));
    expect(
      debugCursorLabelLayoutCounts['a'],
      2,
      reason: 'a colour change must re-lay-out so stale text is never drawn',
    );
  });

  test(
      'a departed cursor is dropped even when an off-screen one takes its '
      'place', () {
    final document = CanvasDocument();
    addTearDown(document.dispose);
    final cursors = _oneCursor();
    addTearDown(cursors.dispose);

    final painter = _painter(cursors, document);
    final canvas = _RecordingCanvas();
    painter.paint(canvas, const Size(400, 400));
    expect(painter.debugLabelCacheSize, 1);

    // user-ada leaves; a new cursor joins far off-screen, so it is culled and never populates the cache, hiding the dead slot from a size-only cleanup trigger.
    cursors.remove('user-ada');
    cursors.upsert(
        id: 'far', x: 100000, y: 100000, label: 'Far', colorIndex: 0);
    painter.paint(canvas, const Size(400, 400));
    expect(
      painter.debugLabelCacheSize,
      0,
      reason: 'the departed cursor is dropped and the off-screen one was never '
          'drawn, so nothing stays cached',
    );
  });

  test('retain drops cached labels for cursors no longer present', () {
    final cache = CursorLabelCache();
    const color = Color(0xFF111111);
    cache.painterFor('a', 'Ada', color);
    cache.painterFor('b', 'Bo', color);
    expect(cache.size, 2);

    cache.retain({'a'});
    expect(cache.size, 1, reason: "b left the call, so its label is dropped");
  });
}
