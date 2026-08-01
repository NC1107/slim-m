// SPDX-License-Identifier: Apache-2.0
/// What the chrome does when the viewer has asked for less motion.
///
/// Two claims, and each is asserted from both sides, because a reduce-motion
/// branch that is always taken passes a one-sided test while quietly removing
/// the animation from everybody: the speaking ring really does pulse by
/// default, and really does stop and grow a second cue when asked; and the
/// tweened controls really do tween by default and jump instantly when asked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required bool reduceMotion,
}) {
  return tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

/// The ring's current alpha, read off the overlay the avatar actually paints.
double _ringAlpha(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(AppSpeakingRing),
      // The glyph's backdrop is a Container too; only the ring is a foreground.
      matching: find.byWidgetPredicate(
        (widget) => widget is Container && widget.foregroundDecoration != null,
      ),
    ),
  );
  final decoration = container.foregroundDecoration! as BoxDecoration;
  return decoration.border!.top.color.a;
}

void main() {
  group('the speaking ring', () {
    testWidgets('pulses, and shows no second cue, by default', (tester) async {
      await _pump(
        tester,
        const AppAvatar(name: 'Ada', speaking: true),
        reduceMotion: false,
      );

      expect(find.byType(AppSpeakingGlyph), findsNothing);
      expect(
        tester.hasRunningAnimations,
        isTrue,
        reason: 'the speaking ring is the one looping animation the chrome '
            'is allowed, and it is what carries speaking when nothing else does',
      );

      final before = _ringAlpha(tester);
      await tester.pump(AppMotion.speakingPulse ~/ 2);
      expect(
        _ringAlpha(tester),
        isNot(closeTo(before, 0.01)),
        reason: 'a ring that holds one alpha across half a cycle is not '
            'pulsing, whatever the controller says it is doing',
      );
    });

    testWidgets('holds still and adds the bar glyph under reduce motion',
        (tester) async {
      await _pump(
        tester,
        const AppAvatar(name: 'Ada', speaking: true),
        reduceMotion: true,
      );

      expect(
        find.byType(AppSpeakingGlyph),
        findsOneWidget,
        reason: 'with the pulse gone the ring alone is indistinguishable from '
            'any other ring, so speaking has to be said a second way',
      );
      expect(
        tester.hasRunningAnimations,
        isFalse,
        reason: 'nothing may keep ticking once the viewer has asked it not to',
      );

      final before = _ringAlpha(tester);
      await tester.pump(AppMotion.speakingPulse * 2);
      expect(_ringAlpha(tester), before);
      expect(before, 1.0,
          reason: 'a stilled ring stops at full strength, not '
              'wherever the pulse happened to be');
    });

    testWidgets('a plain ring colour never brings the glyph with it',
        (tester) async {
      await _pump(
        tester,
        const AppAvatar(name: 'Ada', ringColor: Color(0xFF00FF00)),
        reduceMotion: true,
      );

      expect(find.byType(AppSpeakingRing), findsNothing);
      expect(find.byType(AppSpeakingGlyph), findsNothing);
    });
  });

  group('tweened controls', () {
    testWidgets('the toggle thumb slides by default and jumps when reduced',
        (tester) async {
      for (final reduceMotion in [false, true]) {
        await _pump(
          tester,
          AppToggle(value: false, onChanged: (_) {}, semanticLabel: 'Mute'),
          reduceMotion: reduceMotion,
        );
        await _pump(
          tester,
          AppToggle(value: true, onChanged: (_) {}, semanticLabel: 'Mute'),
          reduceMotion: reduceMotion,
        );
        await tester.pump();

        expect(
          tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).duration,
          reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
        );
        expect(tester.hasRunningAnimations, !reduceMotion);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('the segmented control settles instantly when reduced',
        (tester) async {
      for (final reduceMotion in [false, true]) {
        await _pump(
          tester,
          AppSegmentedControl.inline(
            options: const [
              AppSegmentedOption(label: 'Compact'),
              AppSegmentedOption(label: 'Spacious'),
            ],
            selectedIndex: 0,
            onSegmentSelected: (_) {},
          ),
          reduceMotion: reduceMotion,
        );

        final animated = tester.widgetList<AnimatedContainer>(
          find.byType(AnimatedContainer),
        );
        // Without this the loop below passes on an empty match: widgetList
        // returns an empty iterable rather than failing, so the assertion
        // never ran and the test proved nothing.
        expect(animated, isNotEmpty,
            reason: 'the control has an AnimatedContainer to check');
        for (final container in animated) {
          expect(
            container.duration,
            reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
          );
        }
        await tester.pumpAndSettle();
      }
    });
  });

  group('AppMotion', () {
    testWidgets('a screen reader counts as asking for less motion',
        (tester) async {
      late bool reduced;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: Builder(
            builder: (context) {
              reduced = AppMotion.isReduced(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        reduced,
        isTrue,
        reason: 'a loop nobody can see is noise, and a transition in front of '
            'an announcement is only a delay',
      );
    });

    testWidgets('an untouched setting leaves motion alone', (tester) async {
      late Duration duration;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (context) {
              duration =
                  AppMotion.reduced(context, const Duration(milliseconds: 150));
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(duration, const Duration(milliseconds: 150));
    });
  });

  group('AppMotion.reducedSize', () {
    testWidgets('an untouched setting leaves it at the full duration',
        (tester) async {
      late Duration duration;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (context) {
              duration = AppMotion.reducedSize(context, AppMotion.base);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(duration, AppMotion.base);
    });

    testWidgets('reduced motion never collapses it to a literal zero',
        (tester) async {
      late Duration duration;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              duration = AppMotion.reducedSize(context, AppMotion.base);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        duration,
        isNot(Duration.zero),
        reason: 'RenderAnimatedSize completes a zero-duration controller '
            'synchronously and re-enters markNeedsLayout on itself mid-layout',
      );
    });

    /// `RenderAnimatedSize` restarts its controller every time its child's
    /// size differs from what it last saw; two such changes across
    /// consecutive frames is what reproduces the crash `reducedSize` exists
    /// to avoid. Reverting it to [AppMotion.reduced] fails this test with "A
    /// RenderAnimatedSize was mutated in its own performLayout
    /// implementation."
    testWidgets(
      'an AnimatedSize wired through it survives its child changing size '
      'twice in a row',
      (tester) async {
        Widget frame(bool tall) => MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Center(
                  child: Builder(
                    builder: (context) => AnimatedSize(
                      duration: AppMotion.reducedSize(context, AppMotion.base),
                      child: tall
                          ? const SizedBox(width: 100, height: 100)
                          : const SizedBox(width: 100, height: 0),
                    ),
                  ),
                ),
              ),
            );

        await tester.pumpWidget(frame(false));
        await tester.pumpWidget(frame(true));
        await tester.pump();
        await tester.pumpWidget(frame(false));
        await tester.pump();
      },
    );
  });
}
