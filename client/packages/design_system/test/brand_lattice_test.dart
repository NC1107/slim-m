// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The brand lattice is decoration with one rule attached: under reduce-motion
/// its entrance must not happen at all, not merely happen faster.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: buildTheme(Brightness.dark, AppTokens.dark),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: SizedBox(width: 260, height: 600, child: child)),
      ),
    );

void main() {
  testWidgets('under reduce-motion the square is at rest on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AppBrandLattice(), reduceMotion: true));
    await tester.pump();

    final state = tester.state<AppBrandLatticeState>(
      find.byType(AppBrandLattice),
    );
    expect(state.settled, isTrue, reason: 'no entrance at all, not a fast one');
  });

  testWidgets('otherwise it settles within the slow motion token', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AppBrandLattice()));
    await tester.pump();
    final state = tester.state<AppBrandLatticeState>(
      find.byType(AppBrandLattice),
    );
    expect(state.settled, isFalse, reason: 'the entrance is under way');

    // One frame past the token: a controller completes once elapsed exceeds duration, not equals it.
    await tester.pump(AppMotion.slow + const Duration(milliseconds: 16));
    expect(state.progress, 1.0);
    expect(state.settled, isTrue);
  });

  testWidgets('it renders in both themes without overflowing its box', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(
            brightness,
            brightness == Brightness.dark ? AppTokens.dark : AppTokens.light,
          ),
          home: const Scaffold(
            body: SizedBox(width: 260, height: 600, child: AppBrandLattice()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
