// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Proves `waitUntil` actually discriminates, the same reason
/// `mid_flight_capture_test.dart` exists for its own helper.
///
/// A polling helper that returned without checking anything would make every
/// test using it pass for the wrong reason, which is worse than the guessed
/// delay it replaced.
///
/// None of these uses a timer to make a condition come true later. A bare
/// `Future.delayed` inside `testWidgets` runs on the fake clock, so it never
/// fires while `waitUntil` polls in real time, and it is still pending at
/// teardown - which fails the test for a second, unrelated reason. Wall-clock
/// reads and call counters have no such problem.
library;

import 'package:flutter_test/flutter_test.dart';

import 'async_wait.dart';

void main() {
  testWidgets('polls until the condition holds, then returns', (tester) async {
    // No timer on purpose: see this file's doc for why one would never fire.
    var calls = 0;

    await waitUntil(tester, () => ++calls >= 3);

    expect(calls, greaterThanOrEqualTo(3), reason: 'it really did poll');
  });

  testWidgets('returns immediately when it already holds', (tester) async {
    final started = DateTime.now();

    await waitUntil(tester, () => true);

    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 1)),
      reason: 'a condition already true must not wait out any of the timeout',
    );
  });

  testWidgets('fails, with its reason, when the condition never holds', (
    tester,
  ) async {
    await expectLater(
      () => waitUntil(
        tester,
        () => false,
        timeout: const Duration(milliseconds: 80),
        reason: 'the thing under test never happened',
      ),
      throwsA(
        isA<TestFailure>().having(
          (f) => f.message,
          'message',
          allOf(
            contains('the thing under test never happened'),
            contains('80ms'),
          ),
        ),
      ),
    );
  });

  testWidgets('the timeout is a real ceiling, not advisory', (tester) async {
    // Real wall clock, so it is unaffected by the fake one the test runs on.
    final turnsTrueAt = DateTime.now().add(const Duration(seconds: 30));

    await expectLater(
      () => waitUntil(
        tester,
        () => DateTime.now().isAfter(turnsTrueAt),
        timeout: const Duration(milliseconds: 50),
      ),
      throwsA(isA<TestFailure>()),
    );
  });
}
