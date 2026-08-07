// SPDX-License-Identifier: Apache-2.0
/// [CanvasPresenceTileOverrides]: default state, that each mutator both
/// stores its own field and leaves the others untouched, that [prune] drops
/// exactly what left the roster, and that every mutation notifies.
library;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

void main() {
  test('an unset key defaults to no rect, unlocked, not hidden, in front', () {
    final overrides = CanvasPresenceTileOverrides();

    final state = overrides.stateFor('camera:alice');

    expect(state.rect, isNull);
    expect(state.locked, isFalse);
    expect(state.hidden, isFalse);
    expect(state.sentToBack, isFalse);
  });

  test('setRect stores a rect for its own key only', () {
    final overrides = CanvasPresenceTileOverrides();

    overrides.setRect('camera:alice', const Rect.fromLTWH(10, 20, 30, 40));

    expect(overrides.stateFor('camera:alice').rect,
        const Rect.fromLTWH(10, 20, 30, 40));
    expect(overrides.stateFor('camera:bob').rect, isNull);
  });

  test('setLocked does not touch a rect already recorded', () {
    final overrides = CanvasPresenceTileOverrides();
    overrides.setRect('camera:alice', const Rect.fromLTWH(1, 2, 3, 4));

    overrides.setLocked('camera:alice', true);

    final state = overrides.stateFor('camera:alice');
    expect(state.locked, isTrue);
    expect(state.rect, const Rect.fromLTWH(1, 2, 3, 4));
  });

  test('setSentToBack does not touch locked, hidden or rect', () {
    final overrides = CanvasPresenceTileOverrides();
    overrides.setRect('camera:alice', const Rect.fromLTWH(1, 2, 3, 4));
    overrides.setLocked('camera:alice', true);

    overrides.setSentToBack('camera:alice', true);

    final state = overrides.stateFor('camera:alice');
    expect(state.sentToBack, isTrue);
    expect(state.locked, isTrue);
    expect(state.rect, const Rect.fromLTWH(1, 2, 3, 4));
  });

  test('setSentToBack(false) reverses it, leaving everything else alone', () {
    final overrides = CanvasPresenceTileOverrides();
    overrides.setSentToBack('camera:alice', true);

    overrides.setSentToBack('camera:alice', false);

    expect(overrides.stateFor('camera:alice').sentToBack, isFalse);
  });

  test('setHidden does not touch locked, rect or sentToBack', () {
    final overrides = CanvasPresenceTileOverrides();
    overrides.setRect('camera:alice', const Rect.fromLTWH(1, 2, 3, 4));
    overrides.setLocked('camera:alice', true);
    overrides.setSentToBack('camera:alice', true);

    overrides.setHidden('camera:alice', true);

    final state = overrides.stateFor('camera:alice');
    expect(state.hidden, isTrue);
    expect(state.locked, isTrue);
    expect(state.sentToBack, isTrue);
    expect(state.rect, const Rect.fromLTWH(1, 2, 3, 4));
  });

  test('clearRect drops only the rect, leaving lock and hidden alone', () {
    final overrides = CanvasPresenceTileOverrides();
    overrides.setRect('camera:alice', const Rect.fromLTWH(1, 2, 3, 4));
    overrides.setLocked('camera:alice', true);

    overrides.clearRect('camera:alice');

    final state = overrides.stateFor('camera:alice');
    expect(state.rect, isNull);
    expect(state.locked, isTrue);
  });

  test('hiddenKeys names exactly the keys marked hidden', () {
    final overrides = CanvasPresenceTileOverrides();
    overrides.setHidden('camera:alice', true);
    overrides.setHidden('screen:alice', true);
    overrides.setLocked('camera:bob', true);

    expect(overrides.hiddenKeys.toSet(), {'camera:alice', 'screen:alice'});
  });

  test('prune drops an override for a key no longer present', () {
    final overrides = CanvasPresenceTileOverrides();
    overrides.setRect('camera:alice', const Rect.fromLTWH(1, 2, 3, 4));
    overrides.setRect('camera:bob', const Rect.fromLTWH(5, 6, 7, 8));

    overrides.prune({'camera:bob'});

    expect(overrides.stateFor('camera:alice').rect, isNull);
    expect(
        overrides.stateFor('camera:bob').rect, const Rect.fromLTWH(5, 6, 7, 8));
  });

  test('prune with nothing to drop does not notify', () {
    final overrides = CanvasPresenceTileOverrides();
    overrides.setRect('camera:alice', const Rect.fromLTWH(1, 2, 3, 4));
    var notifications = 0;
    overrides.addListener(() => notifications++);

    overrides.prune({'camera:alice'});

    expect(notifications, 0);
  });

  test(
      'a key is untouched until its rect is set, and setRect ranks keys by '
      'when they were last touched', () {
    final overrides = CanvasPresenceTileOverrides();
    expect(overrides.zFor('camera:alice'), isNull);

    overrides.setRect('camera:alice', const Rect.fromLTWH(0, 0, 10, 10));
    overrides.setRect('camera:bob', const Rect.fromLTWH(0, 0, 10, 10));

    expect(overrides.zFor('camera:alice'),
        lessThan(overrides.zFor('camera:bob')!));
  });

  test('touching a key again moves it to the front of the touch order', () {
    final overrides = CanvasPresenceTileOverrides();
    overrides.setRect('camera:alice', const Rect.fromLTWH(0, 0, 10, 10));
    overrides.setRect('camera:bob', const Rect.fromLTWH(0, 0, 10, 10));

    overrides.setRect('camera:alice', const Rect.fromLTWH(5, 5, 10, 10));

    expect(overrides.zFor('camera:alice'),
        greaterThan(overrides.zFor('camera:bob')!));
  });

  test('prune drops the touch order of a key no longer present', () {
    final overrides = CanvasPresenceTileOverrides();
    overrides.setRect('camera:alice', const Rect.fromLTWH(0, 0, 10, 10));

    overrides.prune(const {});

    expect(overrides.zFor('camera:alice'), isNull);
  });

  test('every mutator notifies listeners exactly once', () {
    final overrides = CanvasPresenceTileOverrides();
    var notifications = 0;
    overrides.addListener(() => notifications++);

    overrides.setRect('camera:alice', const Rect.fromLTWH(1, 2, 3, 4));
    overrides.setLocked('camera:alice', true);
    overrides.setSentToBack('camera:alice', true);
    overrides.setHidden('camera:alice', true);
    overrides.clearRect('camera:alice');
    overrides.prune(const {});

    expect(notifications, 6);
  });
}
