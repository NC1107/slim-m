// SPDX-License-Identifier: Apache-2.0
/// [CanvasSelfPresenceController]: the default state, that hiding and
/// dragging persist to `SharedPreferences`, that a fresh controller (a
/// relaunch, or reopening the canvas) reads a previously persisted value
/// back instead of the default, and that a corner value this build no
/// longer recognises degrades to the default rather than throwing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/providers/canvas_self_presence.dart';

/// A second container over the same mocked prefs store, modelling a
/// relaunch (or reopening the canvas): nothing carries state forward except
/// what was written to (mocked) disk. Awaiting the fresh controller's own
/// [CanvasSelfPresenceController.ready] is what makes this deterministic -
/// no guessing how many event-loop turns a `SharedPreferences` round trip
/// takes.
Future<ProviderContainer> _relaunch() async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await container.read(canvasSelfPresenceProvider.notifier).ready;
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to visible, bottom-right, with nothing stored', () async {
    final container = await _relaunch();

    final state = container.read(canvasSelfPresenceProvider);
    expect(state.hidden, isFalse);
    expect(state.corner, CanvasSelfBubbleCorner.bottomRight);
  });

  test('setHidden persists, and a later launch reads it back', () async {
    final first = ProviderContainer();
    addTearDown(first.dispose);
    await first.read(canvasSelfPresenceProvider.notifier).setHidden(true);
    expect(first.read(canvasSelfPresenceProvider).hidden, isTrue);

    final relaunch = await _relaunch();
    expect(relaunch.read(canvasSelfPresenceProvider).hidden, isTrue);
  });

  test('setCorner persists, and a later launch reads it back', () async {
    final first = ProviderContainer();
    addTearDown(first.dispose);
    await first
        .read(canvasSelfPresenceProvider.notifier)
        .setCorner(CanvasSelfBubbleCorner.topLeft);

    final relaunch = await _relaunch();
    expect(
      relaunch.read(canvasSelfPresenceProvider).corner,
      CanvasSelfBubbleCorner.topLeft,
    );
  });

  test('setHidden(false) reverses it, and that also persists', () async {
    final first = ProviderContainer();
    addTearDown(first.dispose);
    await first.read(canvasSelfPresenceProvider.notifier).setHidden(true);
    await first.read(canvasSelfPresenceProvider.notifier).setHidden(false);

    final relaunch = await _relaunch();
    expect(relaunch.read(canvasSelfPresenceProvider).hidden, isFalse);
  });

  test('a corner string this build does not recognise falls back to the '
      'default rather than throwing', () async {
    SharedPreferences.setMockInitialValues({
      canvasSelfBubbleCornerKey: 'a-corner-from-a-future-version',
    });

    final container = await _relaunch();

    expect(
      container.read(canvasSelfPresenceProvider).corner,
      CanvasSelfBubbleCorner.bottomRight,
    );
  });

  test('hiding right after construction is not clobbered by a load already in '
      'flight', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(canvasSelfPresenceProvider.notifier);

    // Nothing is stored, so the in-flight load would answer `false`; this call must win.
    await notifier.setHidden(true);
    await notifier.ready;

    expect(container.read(canvasSelfPresenceProvider).hidden, isTrue);
  });

  test('hiding right after construction must not blank a corner a prior '
      'session already persisted', () async {
    SharedPreferences.setMockInitialValues({
      canvasSelfBubbleCornerKey: CanvasSelfBubbleCorner.topLeft.name,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(canvasSelfPresenceProvider.notifier);

    // The generation guard only protects "hidden"; corner is the one the load, not this call, would have answered.
    await notifier.setHidden(true);
    await notifier.ready;

    final state = container.read(canvasSelfPresenceProvider);
    expect(state.hidden, isTrue);
    expect(
      state.corner,
      CanvasSelfBubbleCorner.topLeft,
      reason:
          'a call touching only "hidden" must not leave "corner" '
          'stuck at its constructor default just because it happened to '
          'win the race against the load',
    );
  });

  test('dragging to a corner right after construction must not blank a hidden '
      'flag a prior session already persisted', () async {
    SharedPreferences.setMockInitialValues({canvasSelfBubbleHiddenKey: true});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(canvasSelfPresenceProvider.notifier);

    await notifier.setCorner(CanvasSelfBubbleCorner.topLeft);
    await notifier.ready;

    final state = container.read(canvasSelfPresenceProvider);
    expect(state.corner, CanvasSelfBubbleCorner.topLeft);
    expect(
      state.hidden,
      isTrue,
      reason:
          'a call touching only "corner" must not leave "hidden" '
          'stuck at its constructor default just because it happened to '
          'win the race against the load',
    );
  });
}
