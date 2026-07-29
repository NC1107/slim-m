// SPDX-License-Identifier: Apache-2.0
/// The join flow's frame: what the stepper says, and what the brand panel
/// does when there is no room for it.
///
/// The stepper's job is to say how many decisions are left, so the count is
/// the thing pinned here - not the styling.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/onboarding_shell.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _harness(Widget child, {Size size = const Size(1200, 900)}) =>
    MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: child,
      ),
    );

void main() {
  group('the stepper', () {
    testWidgets('announces which step of how many, not just a label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const Scaffold(
            body: OnboardingStepper(current: OnboardingStep.server),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('Step 2 of 3: confirm the server'),
        findsOneWidget,
        reason:
            'the count is the whole reason the stepper exists, so it has '
            'to reach a screen reader as a count',
      );
    });

    testWidgets('steps already passed are ticked, not merely recoloured', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const Scaffold(
            body: OnboardingStepper(current: OnboardingStep.identity),
          ),
        ),
      );

      // Two behind, so two ticks; the current one keeps its number.
      expect(find.byIcon(AppIcons.check), findsNWidgets(2));
      expect(find.text('3'), findsOneWidget);
      expect(
        find.text('1'),
        findsNothing,
        reason: 'done and to-come differ in shape, not only in colour',
      );
    });

    testWidgets('every step is shown, including the ones behind you', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const Scaffold(
            body: SizedBox(
              width: 700,
              child: OnboardingStepper(current: OnboardingStep.server),
            ),
          ),
        ),
      );

      for (final step in OnboardingStep.values) {
        expect(find.text(step.label), findsOneWidget, reason: step.label);
      }
    });

    testWidgets('narrow keeps the numbers and drops the words it cannot fit', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const Scaffold(
            body: SizedBox(
              width: 300,
              child: OnboardingStepper(current: OnboardingStep.server),
            ),
          ),
        ),
      );

      expect(find.text('confirm the server'), findsOneWidget);
      expect(
        find.text('who are you'),
        findsNothing,
        reason: 'the step you are on keeps its words; the rest stay pips',
      );
      // Still three pips, so the count survives.
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('the shell', () {
    testWidgets('shows the brand panel with room, and the wordmark without', (
      tester,
    ) async {
      const marker = Key('form');
      await tester.pumpWidget(
        _harness(
          const OnboardingShell(child: SizedBox(key: marker, height: 40)),
          size: const Size(1200, 900),
        ),
      );
      expect(
        find.textContaining('Open source', findRichText: true),
        findsOneWidget,
      );
      expect(find.byKey(marker), findsOneWidget);

      await tester.pumpWidget(
        _harness(
          const OnboardingShell(child: SizedBox(key: marker, height: 40)),
          size: const Size(420, 900),
        ),
      );
      expect(
        find.textContaining('Open source', findRichText: true),
        findsNothing,
        reason:
            'the pitch is chrome and goes first when the form needs the '
            'width; the wordmark stays so the screen is still identifiable',
      );
      expect(find.text('slim-m'), findsOneWidget);
      expect(find.byKey(marker), findsOneWidget);
    });

    testWidgets('a screen outside the join flow gets no stepper', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(const OnboardingShell(child: SizedBox(height: 40))),
      );
      expect(find.byType(OnboardingStepper), findsNothing);

      await tester.pumpWidget(
        _harness(
          const OnboardingShell(
            step: OnboardingStep.invite,
            child: SizedBox(height: 40),
          ),
        ),
      );
      expect(find.byType(OnboardingStepper), findsOneWidget);
    });
  });
}
