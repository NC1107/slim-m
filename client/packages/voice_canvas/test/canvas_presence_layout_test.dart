// SPDX-License-Identifier: Apache-2.0
/// [CanvasPresenceLayout]: deterministic, order-independent placement.
library;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

void main() {
  test('places each identity in its own non-overlapping tile', () {
    const layout = CanvasPresenceLayout();

    final placed = layout.arrange(['alice', 'bob', 'carol']);

    expect(placed.keys, {'alice', 'bob', 'carol'});
    final rects = placed.values.toList();
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), isFalse);
      }
    }
  });

  test('the same set arranges identically regardless of insertion order', () {
    const layout = CanvasPresenceLayout();

    final forward = layout.arrange(['alice', 'bob', 'carol']);
    final reversed = layout.arrange(['carol', 'bob', 'alice']);

    expect(forward, reversed);
  });

  test('the first tile sits within the default camera\'s initial view', () {
    const layout = CanvasPresenceLayout();

    final placed = layout.arrange(['alice']);

    // The default camera's initial view starts at the world's origin.
    expect(placed['alice']!.left, greaterThan(0));
    expect(placed['alice']!.top, greaterThan(0));
  });

  test('an empty roster places nothing', () {
    const layout = CanvasPresenceLayout();

    expect(layout.arrange(const []), isEmpty);
  });

  test('a second identity sits to the right of the first, not overlapping', () {
    const layout = CanvasPresenceLayout(tileWidth: 100, gap: 10);

    final placed = layout.arrange(['a', 'b']);

    expect(placed['b']!.left, placed['a']!.right + 10);
  });

  test(
      'sizeFor gives each key its own tile size, and the next tile still '
      'starts past the wider one\'s own right edge', () {
    const layout = CanvasPresenceLayout(gap: 10, margin: 0);

    final placed = layout.arrange(
      ['camera:a', 'screen:a'],
      sizeFor: (key) => key.startsWith('screen:')
          ? const Size(360, 200)
          : const Size(100, 80),
    );

    expect(placed['camera:a']!.size, const Size(100, 80));
    expect(placed['screen:a']!.size, const Size(360, 200));
    expect(placed['screen:a']!.left, placed['camera:a']!.right + 10);
  });

  test('sizeFor left null falls back to the uniform tileWidth/tileHeight', () {
    const layout = CanvasPresenceLayout();

    final withCallback = layout.arrange(['alice', 'bob'], sizeFor: null);
    final without = layout.arrange(['alice', 'bob']);

    expect(withCallback, without);
  });
}
