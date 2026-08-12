// SPDX-License-Identifier: Apache-2.0
/// The breathing halo behind a waiting state's glyph: a few breaths on
/// mount, then rest - never an unbounded loop, which would hang every
/// `pumpAndSettle` crossing a waiting screen - and stillness at full
/// strength under reduce motion.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _halo({bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: const Center(
          child: AppBreathingHalo(child: SizedBox(width: 10, height: 10)),
        ),
      ),
    );

double _scale(WidgetTester tester) => tester
    .widget<Transform>(
      find.descendant(
        of: find.byType(AppBreathingHalo),
        matching: find.byType(Transform),
      ),
    )
    .transform
    .storage[0];

void main() {
  testWidgets('the disc breathes on mount, then rests at full strength', (
    tester,
  ) async {
    await tester.pumpWidget(_halo());
    final atRest = _scale(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(_scale(tester), isNot(atRest));

    // Bounded on purpose: a waiting screen must be able to settle.
    await tester.pumpAndSettle();
    expect(_scale(tester), 1.0);
  });

  testWidgets('reduce motion holds it still at full strength', (tester) async {
    await tester.pumpWidget(_halo(reduceMotion: true));
    expect(_scale(tester), 1.0);
    await tester.pump(const Duration(milliseconds: 600));
    expect(_scale(tester), 1.0);
  });
}
