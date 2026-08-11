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

  group('maxRowWidth: a phone held upright', () {
    // Five real camera-on tiles: 24 margin + 5 x 220 + 4 x 24 gaps, so one unbounded row spans 1220 world units against a portrait pane's 390.
    const roster = ['a', 'b', 'c', 'd', 'e'];

    test('unbounded keeps every tile on one row, as it always has', () {
      const layout = CanvasPresenceLayout();

      final placed = layout.arrange(roster);

      expect(placed.values.map((r) => r.top).toSet(), hasLength(1));
      expect(placed['e']!.right, greaterThan(1200));
    });

    test('a portrait-width bound wraps, and every tile lands inside it', () {
      const layout = CanvasPresenceLayout(maxRowWidth: 390);

      final placed = layout.arrange(roster);

      // The finding this exists for: on one row four of the five sat past a 390-wide pane's right edge, reachable only by panning sideways through empty world.
      for (final entry in placed.entries) {
        expect(
          entry.value.right,
          lessThanOrEqualTo(390),
          reason: '${entry.key} runs past the pane it was arranged for',
        );
      }
      expect(placed.values.map((r) => r.top).toSet().length, roster.length);
    });

    test('a desktop-width bound is byte-identical to no bound at all', () {
      const bounded = CanvasPresenceLayout(maxRowWidth: 1400);
      const unbounded = CanvasPresenceLayout();

      expect(bounded.arrange(roster), unbounded.arrange(roster));
    });

    test('rows never overlap once wrapped, whatever the tile heights', () {
      const layout = CanvasPresenceLayout(maxRowWidth: 390);

      final placed = layout.arrange(
        ['camera:a', 'camera:b', 'screen:a'],
        sizeFor: (key) => key.startsWith('screen:')
            ? const Size(360, 203)
            : const Size(220, 160),
      );

      final rects = placed.values.toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
    });

    test('a tile wider than the whole bound still lands rather than looping',
        () {
      const layout = CanvasPresenceLayout(maxRowWidth: 100, margin: 24);

      // Sorted, so 'a-wide' is placed first and 'b-after' is the one that has to decide whether to wrap.
      final placed = layout.arrange(
        ['a-wide', 'b-after'],
        sizeFor: (_) => const Size(360, 203),
      );

      expect(placed['a-wide']!.left, 24);
      // Never stacked into the same row it could not fit in either.
      expect(placed['b-after']!.top, greaterThan(placed['a-wide']!.top));
    });

    test('wrapping stays order-independent, the whole point of sorting', () {
      const layout = CanvasPresenceLayout(maxRowWidth: 390);

      expect(layout.arrange(roster), layout.arrange(roster.reversed));
    });
  });
}
