// SPDX-License-Identifier: Apache-2.0
/// [awaitBootstrapWithSplashFloor]'s own timing: a floor on desktop, never
/// added latency on top of a slow bootstrap, no floor at all off desktop, and
/// - for the splash on/off preference - an explicit [Duration.zero] floor
/// that behaves like no floor at all rather than a second code path.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/splash_floor.dart';

void main() {
  test('an instant bootstrap on desktop still waits out the floor', () {
    fakeAsync((async) {
      var completed = false;
      unawaited(
        awaitBootstrapWithSplashFloor(
          () async {},
          desktop: true,
        ).whenComplete(() => completed = true),
      );

      async.flushMicrotasks();
      expect(completed, isFalse, reason: 'the floor has not elapsed yet');

      async.elapse(minSplashDuration - const Duration(milliseconds: 1));
      expect(completed, isFalse, reason: 'one millisecond short of the floor');

      async.elapse(const Duration(milliseconds: 1));
      expect(completed, isTrue);
    });
  });

  test('a bootstrap slower than the floor governs, the floor adds nothing '
      'on top of it', () {
    fakeAsync((async) {
      final slow = minSplashDuration * 3;
      var completed = false;
      unawaited(
        awaitBootstrapWithSplashFloor(
          () => Future<void>.delayed(slow),
          desktop: true,
        ).whenComplete(() => completed = true),
      );

      async.elapse(slow - const Duration(milliseconds: 1));
      expect(completed, isFalse);

      async.elapse(const Duration(milliseconds: 1));
      expect(
        completed,
        isTrue,
        reason:
            'resolves exactly when the slow bootstrap does, no extra '
            'delay stacked on top',
      );
    });
  });

  test('off desktop, an instant bootstrap resolves instantly with no floor '
      'applied', () {
    fakeAsync((async) {
      var completed = false;
      unawaited(
        awaitBootstrapWithSplashFloor(
          () async {},
          desktop: false,
        ).whenComplete(() => completed = true),
      );

      async.flushMicrotasks();
      expect(completed, isTrue);
    });
  });

  test('a splash disabled on desktop passes a zero floor, which adds no '
      'dwell at all to an instant bootstrap', () {
    fakeAsync((async) {
      var completed = false;
      unawaited(
        awaitBootstrapWithSplashFloor(
          () async {},
          desktop: true,
          floor: Duration.zero,
        ).whenComplete(() => completed = true),
      );

      // A zero-duration Future.delayed still needs a timer tick, not flushMicrotasks.
      async.elapse(Duration.zero);
      expect(completed, isTrue);
    });
  });

  test('a splash disabled on desktop never pads a slow bootstrap either - '
      'the zero floor resolves no later than the bootstrap itself', () {
    fakeAsync((async) {
      final slow = minSplashDuration * 3;
      var completed = false;
      unawaited(
        awaitBootstrapWithSplashFloor(
          () => Future<void>.delayed(slow),
          desktop: true,
          floor: Duration.zero,
        ).whenComplete(() => completed = true),
      );

      async.elapse(slow - const Duration(milliseconds: 1));
      expect(completed, isFalse);

      async.elapse(const Duration(milliseconds: 1));
      expect(completed, isTrue);
    });
  });

  for (final floor in [
    const Duration(milliseconds: 500),
    minSplashDuration,
    const Duration(milliseconds: 1500),
  ]) {
    test('each named splash duration is honoured as the floor ($floor)', () {
      fakeAsync((async) {
        var completed = false;
        unawaited(
          awaitBootstrapWithSplashFloor(
            () async {},
            desktop: true,
            floor: floor,
          ).whenComplete(() => completed = true),
        );

        async.elapse(floor - const Duration(milliseconds: 1));
        expect(completed, isFalse);

        async.elapse(const Duration(milliseconds: 1));
        expect(completed, isTrue);
      });
    });
  }
}
