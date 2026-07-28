// SPDX-License-Identifier: Apache-2.0
/// Widget tests for the form controls in `components/forms`.
///
/// The slider's "tall, muted, metered with ticks" case exists because the custom
/// track and thumb paint code is the newest, highest-risk part of that widget.
/// It exercises every optional feature at once so a bad rect (for example a
/// meter fraction that clips negative) surfaces here rather than the first time
/// a caller combines them.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('AppInput', () {
    testWidgets('shows its placeholder', (tester) async {
      await tester
          .pumpWidget(_wrap(const AppInput(placeholder: 'Search messages')));

      expect(find.text('Search messages'), findsOneWidget);
    });

    testWidgets('surfaces an error state as visible text', (tester) async {
      await tester.pumpWidget(
          _wrap(const AppInput(errorText: 'This field is required')));

      expect(find.text('This field is required'), findsOneWidget);
    });

    testWidgets('reports focus when the field is tapped', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
          _wrap(AppInput(focusNode: focusNode, placeholder: 'Name')));
      expect(focusNode.hasFocus, isFalse);

      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);
    });
  });

  group('AppChip', () {
    testWidgets('reaction variant shows its count and reflects active',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppChip.reaction(
                  emoji: '\u{1F44D}', count: 3, active: true, onTap: () {}),
              AppChip.reaction(
                  emoji: '\u{1F44D}', count: 5, active: false, onTap: () {}),
            ],
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);

      // Active state is not colour alone: it also carries a heavier weight.
      final activeCount = tester.widget<Text>(find.text('3'));
      final inactiveCount = tester.widget<Text>(find.text('5'));
      expect(activeCount.style?.fontWeight, AppWeights.semi);
      expect(inactiveCount.style?.fontWeight, AppWeights.regular);
    });

    testWidgets('reaction glyph resolves a colour emoji fallback',
        (tester) async {
      await tester.pumpWidget(
        _wrap(AppChip.reaction(
            emoji: '\u{1F44D}', count: 1, active: false, onTap: () {})),
      );

      // Unnamed, fontconfig hands back monochrome Noto Emoji on Fedora.
      final resolved = tester
          .renderObject<RenderParagraph>(find.text('\u{1F44D}'))
          .text
          .style;
      expect(resolved?.fontFamilyFallback, contains('Noto Color Emoji'));
    });

    testWidgets('operator variant renders as a non-interactive span',
        (tester) async {
      await tester
          .pumpWidget(_wrap(const AppChip.operator(label: 'from:priya')));

      expect(find.text('from:priya'), findsOneWidget);
      // No button semantics at all: this variant is a static token, not a
      // control, so there is nothing for FocusableTapTarget to wrap.
      expect(find.byType(GestureDetector), findsNothing);
    });
  });

  group('AppToggle', () {
    testWidgets('flips and reports its value through onChanged',
        (tester) async {
      bool? reported;
      await tester.pumpWidget(
          _wrap(AppToggle(value: false, onChanged: (v) => reported = v)));

      await tester.tap(find.byType(AppToggle));
      await tester.pump();

      expect(reported, isTrue);
    });

    testWidgets('wires no tap handler when disabled', (tester) async {
      await tester
          .pumpWidget(_wrap(const AppToggle(value: false, onChanged: null)));

      // A disabled toggle must not merely ignore the callback: the tap handler
      // is absent, so assistive tech reports it non-interactive, not a button.
      final gestureDetector =
          tester.widget<GestureDetector>(find.byType(GestureDetector));
      expect(gestureDetector.onTap, isNull);

      await tester.tap(find.byType(AppToggle));
      await tester.pump();
    });

    testWidgets('a locked toggle reports on but wires no tap handler',
        (tester) async {
      var called = false;
      await tester.pumpWidget(
        _wrap(AppToggle(
            value: true, locked: true, onChanged: (v) => called = true)),
      );

      final gestureDetector =
          tester.widget<GestureDetector>(find.byType(GestureDetector));
      expect(gestureDetector.onTap, isNull);

      await tester.tap(find.byType(AppToggle));
      await tester.pump();

      expect(called, isFalse);
    });
  });

  group('AppSegmentedControl', () {
    testWidgets(
        'inline variant reports the selected index and signals it beyond colour',
        (tester) async {
      var selectedIndex = 0;
      int? reported;

      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) => AppSegmentedControl.inline(
              options: const [
                AppSegmentedOption(label: 'Day'),
                AppSegmentedOption(label: 'Week')
              ],
              selectedIndex: selectedIndex,
              onSegmentSelected: (i) {
                reported = i;
                setState(() => selectedIndex = i);
              },
            ),
          ),
        ),
      );

      var dayText = tester.widget<Text>(find.text('Day'));
      var weekText = tester.widget<Text>(find.text('Week'));
      // Inline selection is never accent-coloured: a raised surface plus a
      // border plus weight carries it instead.
      expect(dayText.style?.fontWeight, AppWeights.medium);
      expect(weekText.style?.fontWeight, AppWeights.regular);

      await tester.tap(find.text('Week'));
      await tester.pump();

      expect(reported, 1);

      dayText = tester.widget<Text>(find.text('Day'));
      weekText = tester.widget<Text>(find.text('Week'));
      expect(dayText.style?.fontWeight, AppWeights.regular);
      expect(weekText.style?.fontWeight, AppWeights.medium);
    });

    testWidgets('cards variant shows a check glyph only on the selected option',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppSegmentedControl.cards(
            options: const [
              AppSegmentedOption(
                  label: 'Official server', hint: 'slim.npc-server.top'),
              AppSegmentedOption(label: 'Self-hosted', hint: '10.0.0.100:8095'),
            ],
            selectedIndex: 0,
            onSegmentSelected: (_) {},
          ),
        ),
      );

      expect(find.text('Official server'), findsOneWidget);
      expect(find.text('slim.npc-server.top'), findsOneWidget);
      expect(find.byIcon(AppIcons.check), findsOneWidget);
    });
  });

  group('AppSlider', () {
    testWidgets('reports value changes through onChanged', (tester) async {
      double? reported;

      await tester.pumpWidget(
        _wrap(SizedBox(
            width: 200,
            child: AppSlider(value: 20, onChanged: (v) => reported = v))),
      );

      await tester.drag(find.byType(Slider), const Offset(100, 0));
      await tester.pump();

      expect(reported, isNotNull);
    });

    testWidgets('tall variant renders without a meter or ticks supplied',
        (tester) async {
      await tester.pumpWidget(_wrap(SizedBox(
          width: 200,
          child: AppSlider(value: 40, tall: true, onChanged: (_) {}))));

      expect(find.byType(AppSlider), findsOneWidget);
    });

    testWidgets('tall, muted, metered slider with ticks paints without error',
        (tester) async {
      // Every optional feature at once, because the custom paint code is this
      // widget's highest risk. See the library doc at the top of the file.
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 200,
            child: AppSlider(
              value: 65,
              tall: true,
              meter: 80,
              muted: true,
              ticks: const ['Quiet', 'Normal', 'Loud'],
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(AppSlider), findsOneWidget);
    });

    testWidgets('ticks render as a row with the second entry picked out',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 200,
            child: AppSlider(
              value: 50,
              onChanged: (_) {},
              ticks: const ['Small', 'Default', 'Large'],
            ),
          ),
        ),
      );

      expect(find.text('Small'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Large'), findsOneWidget);

      final defaultTick = tester.widget<Text>(find.text('Default'));
      final smallTick = tester.widget<Text>(find.text('Small'));
      expect(defaultTick.style?.color, isNot(smallTick.style?.color));
    });
  });
}
