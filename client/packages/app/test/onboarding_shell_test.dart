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
            body: OnboardingStepper(current: OnboardingStep.identity),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('Step 2 of 2: who are you'),
        findsOneWidget,
        reason:
            'the count is the whole reason the stepper exists, so it has '
            'to reach a screen reader as a count - and as the count of the '
            'two panes the join flow actually has, not a third that no '
            'production widget ever reaches',
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

      // One behind, so one tick; the current one keeps its number.
      expect(find.byIcon(AppIcons.check), findsNWidgets(1));
      expect(find.text('2'), findsOneWidget);
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
              child: OnboardingStepper(current: OnboardingStep.identity),
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
              child: OnboardingStepper(current: OnboardingStep.invite),
            ),
          ),
        ),
      );

      expect(find.text('invite'), findsOneWidget);
      expect(
        find.text('who are you'),
        findsNothing,
        reason: 'the step you are on keeps its words; the rest stay pips',
      );
      // Still both pips, so the count survives.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('the shell', () {
    testWidgets('keeps the brand panel with room and drops it without', (
      tester,
    ) async {
      const marker = Key('form');
      await tester.pumpWidget(
        _harness(
          const OnboardingShell(child: SizedBox(key: marker, height: 40)),
          size: const Size(1200, 900),
        ),
      );
      // Just the mark for now; what is pinned is that it is there at all.
      expect(find.byType(AppBrandMark), findsOneWidget);
      expect(find.byKey(marker), findsOneWidget);

      await tester.pumpWidget(
        _harness(
          const OnboardingShell(child: SizedBox(key: marker, height: 40)),
          size: const Size(420, 900),
        ),
      );
      // One mark, not two, so the panel really did collapse.
      expect(find.byType(AppBrandMark), findsOneWidget);
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

  group('ServerIdentityChip', () {
    Future<void> pump(WidgetTester tester, ServerIdentityStatus status) {
      return tester.pumpWidget(
        _harness(
          Scaffold(
            body: ServerIdentityChip(
              spaceName: 'My Space',
              host: 'chat.example',
              status: status,
            ),
          ),
        ),
      );
    }

    testWidgets('confirmed shows the tick, labelled for a screen reader', (
      tester,
    ) async {
      await pump(tester, ServerIdentityStatus.confirmed);

      expect(find.byIcon(AppIcons.check), findsOneWidget);
      expect(find.byIcon(AppIcons.danger), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('confirmed', caseSensitive: false)),
        findsOneWidget,
      );
    });

    testWidgets('unknown shows neither glyph, but still carries a label', (
      tester,
    ) async {
      await pump(tester, ServerIdentityStatus.unknown);

      expect(find.byIcon(AppIcons.check), findsNothing);
      expect(find.byIcon(AppIcons.danger), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('not yet confirmed')),
        findsOneWidget,
      );
    });

    testWidgets(
      'mismatch is the danger glyph, never the same as a confirmed tick',
      (tester) async {
        await pump(tester, ServerIdentityStatus.mismatch);

        expect(find.byIcon(AppIcons.danger), findsOneWidget);
        expect(
          find.byIcon(AppIcons.check),
          findsNothing,
          reason: 'a mismatch must never render as the same tick as success',
        );
        expect(find.bySemanticsLabel(RegExp('does not match')), findsOneWidget);
      },
    );

    testWidgets(
      'confirmed carries a visible word beside the glyph, not only a screen-reader label',
      (tester) async {
        await pump(tester, ServerIdentityStatus.confirmed);

        expect(find.text('Confirmed'), findsOneWidget);
      },
    );

    testWidgets(
      'mismatch carries a visible word beside the glyph, not only a screen-reader label',
      (tester) async {
        await pump(tester, ServerIdentityStatus.mismatch);

        expect(find.text('Changed'), findsOneWidget);
      },
    );

    testWidgets(
      'unknown renders no visible word, staying as quiet as the glyph',
      (tester) async {
        await pump(tester, ServerIdentityStatus.unknown);

        expect(find.text('Confirmed'), findsNothing);
        expect(find.text('Changed'), findsNothing);
      },
    );
  });
}
