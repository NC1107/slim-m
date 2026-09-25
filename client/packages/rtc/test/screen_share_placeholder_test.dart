// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// `ScreenSharePlaceholder`: the pulsing-dots loading cue shown before a
/// screen share's first frame, replacing the old "Waiting for the shared
/// screen..." sentence that stayed drawn once frames were already flowing
/// (see `first_frame_gate_test.dart` for the gating mechanism itself, which
/// this reuses unchanged).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_rtc/src/first_frame_gate.dart';
import 'package:slimm_rtc/src/screen_share_view.dart';

const _label = 'Loading screen share';

Widget _wrap(Widget child, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: child,
      ),
    );

void main() {
  testWidgets('carries a semantics label for what the dots mean', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const ScreenSharePlaceholder()));
    await tester.pump();

    expect(find.bySemanticsLabel(_label), findsOneWidget);
  });

  testWidgets('the three dots animate through different opacities over time', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const ScreenSharePlaceholder()));
    await tester.pump();
    final before = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .toList();

    await tester.pump(const Duration(milliseconds: 300));
    final after = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .toList();

    expect(
      before,
      isNot(equals(after)),
      reason: 'the loop should have moved the dots along by 300ms',
    );
  });

  testWidgets('reduced motion holds every dot at full, static opacity', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const ScreenSharePlaceholder(), reduceMotion: true),
    );
    await tester.pump();
    final first = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .toList();

    await tester.pump(const Duration(milliseconds: 500));
    final second = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .toList();

    expect(first, everyElement(1.0));
    expect(second, equals(first), reason: 'reduced motion never animates');
    expect(
      find.bySemanticsLabel(_label),
      findsOneWidget,
      reason: 'the meaning still reaches a screen reader without motion',
    );
  });

  testWidgets(
    'wired into FirstFrameReveal: shown before the frame, gone once it lands',
    (tester) async {
      final tracker = FirstFrameTracker();
      await tester.pumpWidget(
        _wrap(
          FirstFrameReveal(
            tracker: tracker,
            placeholder: const ScreenSharePlaceholder(),
            child: const Text('VIDEO'),
          ),
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel(_label), findsOneWidget);
      expect(find.text('VIDEO'), findsOneWidget);

      tracker.markFirstFrame();
      await tester.pump();

      expect(
        find.bySemanticsLabel(_label),
        findsNothing,
        reason: 'no placeholder is left drawn over a share that is playing',
      );
      expect(find.text('VIDEO'), findsOneWidget);
    },
  );
}
