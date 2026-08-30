// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The debug log's own `ExpansionTile` (an entry with a stack trace) drives
/// its expand/collapse with a plain `AnimationController` Flutter owns,
/// keyed to the platform's own reduce-motion feature rather than this app's
/// `MediaQuery` override - the same gap `sheet_test.dart` covers for
/// `showAppSheet`, on a widget that never goes through it.
///
/// Measured on the tile's own rendered height, not `hasRunningAnimations`:
/// tapping it also starts the row's own `InkWell` ripple, a second, genuinely
/// unrelated animation that is still ticking well past both cases' own
/// transition duration, which would make that a false positive either way.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/diagnostics/debug_log.dart';
import 'package:slimm_app/src/screens/debug_log_screen.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _harness({required bool reduceMotion}) => ProviderScope(
  overrides: [
    debugLogProvider.overrideWith(
      (ref) => DebugLog()
        ..record(
          'flutter',
          'a caught exception',
          detail: 'the full stack trace',
        ),
    ),
  ],
  child: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: MaterialApp(
      theme: buildTheme(Brightness.dark, AppTokens.dark),
      home: const DebugLogScreen(),
    ),
  ),
);

void main() {
  testWidgets('expanding an entry is instant under reduce motion', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(reduceMotion: true));
    await tester.tap(find.byType(ExpansionTile));
    await tester.pump();

    final justAfterTap = tester.getSize(find.byType(ExpansionTile)).height;
    await tester.pumpAndSettle();
    final settled = tester.getSize(find.byType(ExpansionTile)).height;

    expect(
      justAfterTap,
      settled,
      reason: 'nothing may keep growing once the viewer has asked it not to',
    );
  });

  testWidgets('expanding an entry still animates by default', (tester) async {
    await tester.pumpWidget(_harness(reduceMotion: false));
    await tester.tap(find.byType(ExpansionTile));
    await tester.pump();

    final justAfterTap = tester.getSize(find.byType(ExpansionTile)).height;
    await tester.pumpAndSettle();
    final settled = tester.getSize(find.byType(ExpansionTile)).height;

    expect(
      justAfterTap,
      lessThan(settled),
      reason:
          "a viewer who asked for nothing keeps the tile's own stock "
          "expansion rather than this app's override collapsing it",
    );
  });
}
