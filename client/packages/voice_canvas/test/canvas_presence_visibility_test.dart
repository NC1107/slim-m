// SPDX-License-Identifier: Apache-2.0
/// [CanvasPresenceVisibility]: the enter/exit hysteresis band.
library;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

void main() {
  const viewport = Rect.fromLTWH(0, 0, 1000, 1000);

  test('a bubble inside the viewport mounts', () {
    final visibility = CanvasPresenceVisibility();

    final visible = visibility.update(viewport, {
      'alice': const Rect.fromLTWH(100, 100, 50, 50),
    });

    expect(visible, {'alice'});
  });

  test('a bubble far outside both bands never mounts', () {
    final visibility = CanvasPresenceVisibility(
      enterMargin: 100,
      exitMargin: 300,
    );

    final visible = visibility.update(viewport, {
      'alice': const Rect.fromLTWH(5000, 5000, 50, 50),
    });

    expect(visible, isEmpty);
  });

  test(
    'once mounted, a bubble stays mounted inside the wider exit band even '
    'after it leaves the narrower enter band - the flicker guard this class '
    'exists for',
    () {
      final visibility = CanvasPresenceVisibility(
        enterMargin: 50,
        exitMargin: 400,
      );

      // Just inside the enter band: mounts.
      final first = visibility.update(viewport, {
        'alice': const Rect.fromLTWH(1010, 0, 50, 50),
      });
      expect(first, {'alice'});

      // Past the enter band but still inside the exit band: stays mounted.
      final second = visibility.update(viewport, {
        'alice': const Rect.fromLTWH(1200, 0, 50, 50),
      });
      expect(second, {'alice'});
    },
  );

  test('a bubble that drifts past the exit band unmounts', () {
    final visibility = CanvasPresenceVisibility(
      enterMargin: 50,
      exitMargin: 400,
    );

    visibility.update(viewport, {
      'alice': const Rect.fromLTWH(1010, 0, 50, 50),
    });
    final after = visibility.update(viewport, {
      'alice': const Rect.fromLTWH(1500, 0, 50, 50),
    });

    expect(after, isEmpty);
  });

  test('an id dropped from the roster unmounts even if it was visible', () {
    final visibility = CanvasPresenceVisibility();

    visibility.update(viewport, {
      'alice': const Rect.fromLTWH(100, 100, 50, 50),
    });
    final after = visibility.update(viewport, const {});

    expect(after, isEmpty);
  });

  test(
      'a fresh bubble right at the boundary of a stale enter band does not '
      're-mount using the old enter test once already tracked as unmounted',
      () {
    final visibility = CanvasPresenceVisibility(
      enterMargin: 50,
      exitMargin: 400,
    );

    // Never mounted, sitting just past the enter band alone.
    final visible = visibility.update(viewport, {
      'alice': const Rect.fromLTWH(1060, 0, 50, 50),
    });

    expect(visible, isEmpty);
  });

  test('rejects an exit band tighter than the enter band', () {
    expect(
      () => CanvasPresenceVisibility(enterMargin: 500, exitMargin: 100),
      throwsA(isA<AssertionError>()),
    );
  });
}
