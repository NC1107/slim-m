// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// [AppTouchHitArea] pads what a finger can press without moving what is drawn.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Future<int> _tapsFrom(
  WidgetTester tester, {
  required bool touch,
  Alignment alignment = Alignment.center,
  required Offset from,
}) async {
  var taps = 0;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: AppTouchHitArea(
          touch: touch,
          alignment: alignment,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox(width: 20, height: 20),
          ),
        ),
      ),
    ),
  );
  final box = tester.getRect(find.byType(GestureDetector));
  await tester.tapAt(box.topLeft + from);
  return taps;
}

void main() {
  testWidgets('keeps the drawn size', (tester) async {
    await _tapsFrom(tester, touch: true, from: const Offset(10, 10));
    expect(tester.getSize(find.byType(GestureDetector)), const Size(20, 20));
    expect(tester.getSize(find.byType(AppTouchHitArea)), const Size(20, 20));
  });

  testWidgets('presses from 12pt outside a 20pt box at touch density', (
    tester,
  ) async {
    expect(
      await _tapsFrom(tester, touch: true, from: const Offset(-11, -11)),
      1,
    );
    expect(await _tapsFrom(tester, touch: true, from: const Offset(31, 31)), 1);
    expect(
        await _tapsFrom(tester, touch: true, from: const Offset(-13, 10)), 0);
  });

  testWidgets('is inert when the layout is not at touch density', (
    tester,
  ) async {
    expect(
      await _tapsFrom(tester, touch: false, from: const Offset(-11, -11)),
      0,
    );
  });

  testWidgets('topLeft sends the extra right and down only', (tester) async {
    const a = Alignment.topLeft;
    expect(
      await _tapsFrom(tester,
          touch: true, alignment: a, from: const Offset(40, 40)),
      1,
    );
    expect(
      await _tapsFrom(tester,
          touch: true, alignment: a, from: const Offset(-2, 10)),
      0,
    );
  });
}
