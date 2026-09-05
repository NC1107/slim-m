// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// `AppListRow`'s `mentioned` state, split out of `surfaces_test.dart` to
/// keep that file under the review budget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Future<void> _pump(WidgetTester tester, Widget child, {AppTokens? tokens}) {
  final t = tokens ?? AppTokens.light;
  return tester.pumpWidget(
    MaterialApp(
        theme: buildTheme(Brightness.light, t),
        home: Scaffold(body: Center(child: child))),
  );
}

void main() {
  group('AppListRow mentioned', () {
    testWidgets(
        'mentioned paints the dot in accentFill and reads as a distinct key from a plain unread dot',
        (tester) async {
      const tokens = AppTokens.light;

      await _pump(
        tester,
        const SizedBox(
            width: 240, child: AppListRow(label: 'general', mentioned: true)),
      );
      expect(
        find.byKey(AppListRow.mentionDotKey),
        findsOneWidget,
        reason: 'a mention must be findable by its own key, not by colour',
      );
      expect(
        find.byKey(AppListRow.unreadDotKey),
        findsNothing,
        reason: 'the plain unread dot and the mention dot are never both shown',
      );
      final dot = tester.widget<DecoratedBox>(
        find.byKey(AppListRow.mentionDotKey),
      );
      expect(
        (dot.decoration as BoxDecoration).color,
        tokens.accentFill,
        reason: 'a mention is one of the seven closed accent roles',
      );
    });

    testWidgets('mentioned is emphasised the same way selected or unread is',
        (tester) async {
      await _pump(tester,
          const SizedBox(width: 240, child: AppListRow(label: 'general')));
      final plainStyle = tester.widget<Text>(find.text('general')).style!;

      await _pump(
        tester,
        const SizedBox(
            width: 240, child: AppListRow(label: 'general', mentioned: true)),
      );
      final mentionedStyle = tester.widget<Text>(find.text('general')).style!;
      expect(mentionedStyle.fontWeight, AppWeights.medium);
      expect(mentionedStyle.fontWeight, isNot(plainStyle.fontWeight));
    });
  });
}
