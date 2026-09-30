// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The 30px pointer hit box is the whole box, not just the 28px plate in it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

void main() {
  testWidgets('the edges of the hit box, outside the plate, still press', (
    tester,
  ) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          body: Center(
            child: AppTouchTargets(
              enabled: false,
              child: AppIconButton(
                icon: AppIcons.settings,
                semanticLabel: 'Settings',
                onPressed: () => pressed++,
              ),
            ),
          ),
        ),
      ),
    );
    final box = tester.getRect(find.byType(AppIconButton));
    expect(box.size, const Size.square(AppSizes.rowPointer));
    for (final point in [
      box.topLeft + const Offset(0.5, 0.5),
      box.bottomRight - const Offset(0.5, 0.5),
    ]) {
      await tester.tapAt(point);
    }
    expect(pressed, 2);
  });
}
