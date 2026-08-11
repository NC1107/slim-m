// SPDX-License-Identifier: Apache-2.0
/// The Discord-style startup screen: renders the brand mark, and honours
/// reduce-motion the same way every other animated surface in this app
/// does - through [AppFadeIn], not a bespoke animation of its own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/startup_screen.dart';
import 'package:slimm_design_system/design_system.dart';

void main() {
  testWidgets('renders the brand mark', (tester) async {
    await tester.pumpWidget(const StartupApp());

    expect(find.byType(AppBrandMark), findsOneWidget);
  });

  testWidgets('fades in by default and holds no running animation once '
      'reduce-motion is on', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: StartupApp(),
      ),
    );
    await tester.pump();

    expect(
      tester.hasRunningAnimations,
      isFalse,
      reason: 'a loop nobody can see is noise, matching AppMotion elsewhere',
    );
  });

  testWidgets('animates in by default when motion is not reduced', (
    tester,
  ) async {
    await tester.pumpWidget(const StartupApp());
    await tester.pump();

    expect(tester.hasRunningAnimations, isTrue);
  });
}
