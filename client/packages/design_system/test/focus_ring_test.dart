// SPDX-License-Identifier: Apache-2.0
/// Guards [AppFocusRing]'s own contract: transparent (but space-reserving)
/// until the wrapped control reports focus, then [AppTokens.focusRing].
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Container _outerContainer(WidgetTester tester) =>
    tester.widget<Container>(find.byType(Container).first);

void main() {
  testWidgets('draws no ring, but reserves its space, until focused', (
    tester,
  ) async {
    late ValueChanged<bool> reportFocus;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          body: AppFocusRing(
            radius: 6,
            builder: (context, onFocusChange) {
              reportFocus = onFocusChange;
              return const SizedBox(width: 40, height: 40);
            },
          ),
        ),
      ),
    );

    final beforeDecoration =
        _outerContainer(tester).decoration! as BoxDecoration;
    expect(beforeDecoration.border, isA<Border>());
    expect(
      (beforeDecoration.border! as Border).top.color,
      Colors.transparent,
    );
    expect((beforeDecoration.border! as Border).top.width, focusRingWidth);

    reportFocus(true);
    await tester.pump();

    final afterDecoration =
        _outerContainer(tester).decoration! as BoxDecoration;
    expect(
      (afterDecoration.border! as Border).top.color,
      AppTokens.light.focusRing,
    );
  });

  testWidgets('drops the ring again once focus moves elsewhere', (
    tester,
  ) async {
    late ValueChanged<bool> reportFocus;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: Scaffold(
          body: AppFocusRing(
            radius: 6,
            builder: (context, onFocusChange) {
              reportFocus = onFocusChange;
              return const SizedBox(width: 40, height: 40);
            },
          ),
        ),
      ),
    );

    reportFocus(true);
    await tester.pump();
    reportFocus(false);
    await tester.pump();

    final decoration = _outerContainer(tester).decoration! as BoxDecoration;
    expect((decoration.border! as Border).top.color, Colors.transparent);
  });
}
