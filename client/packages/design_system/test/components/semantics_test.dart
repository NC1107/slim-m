// SPDX-License-Identifier: Apache-2.0
/// A screen reader must announce each control once.
///
/// Wrapping a `Text` child inside a `Semantics(label: ...)` node merges the two
/// rather than replacing one with the other, so the label is read out twice:
/// "Save, Save". It is invisible on screen, silent in the analyzer, and only
/// audible to the people who depend on it, which is why it needs a test rather
/// than a review.
///
/// It was found in `AppButton`, `AppBadge` and `AppAvatar` by a test that
/// happened to look for the label, and suspected in the components that carry a
/// label the same way. This checks all of them at once, so the next component
/// to grow a `Semantics` wrapper is covered on the day it is written.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.dark, AppTokens.dark),
      home: Scaffold(body: Center(child: child)),
    );

/// Fails unless exactly one node carries [label] as its accessible name.
///
/// A count of zero is the interesting case, and it has two causes that look
/// identical here: the control has no accessible name at all, or its
/// `Semantics(label:)` merged with a `Text` child carrying the same string into
/// "general, general", which matches neither. Both are bugs, and both are
/// silent on screen and in the analyzer.
void _announcedOnce(WidgetTester tester, String label) {
  final matches = find.bySemanticsLabel(label).evaluate().length;
  expect(
    matches,
    1,
    reason: 'expected exactly one node named "$label", found $matches. '
        'Zero usually means a Semantics wrapper merged with its own Text '
        'child; wrap the visible child in ExcludeSemantics.',
  );
}

void main() {
  testWidgets('AppButton announces its label once', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(AppButton(label: 'Save', onPressed: () {})));
    _announcedOnce(tester, 'Save');
    handle.dispose();
  });

  testWidgets('AppListRow announces its label once', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const AppListRow(label: 'general')));
    _announcedOnce(tester, 'general');
    handle.dispose();
  });

  testWidgets('AppMenuItem announces its label once', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(AppMenuItem(label: 'Delete message', onTap: () {})),
    );
    _announcedOnce(tester, 'Delete message');
    handle.dispose();
  });

  testWidgets('AppBadge announces its content once', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(const AppBadge(variant: AppBadgeVariant.tag, label: 'webhook')),
    );
    _announcedOnce(tester, 'webhook');
    handle.dispose();
  });

  testWidgets('a presence dot names its state rather than its colour',
      (tester) async {
    // The dot has no text, so the label is the only thing carrying its state to
    // a screen reader; "green circle" describes pixels and says nothing.
    for (final status in AppPresence.values) {
      await tester.pumpWidget(_host(AppStatusDot(status: status)));
      final semantics = tester.getSemantics(find.byType(AppStatusDot));
      expect(
        semantics.label.trim(),
        isNotEmpty,
        reason: '\$status has no accessible name',
      );
      expect(
        semantics.label.toLowerCase(),
        isNot(anyOf(contains('green'), contains('red'), contains('amber'))),
        reason: '\$status is announced by colour rather than by meaning',
      );
    }
  });
}
