// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Who is talking reaches the accessible name, not only the ring.
///
/// The speaking ring was the only thing carrying it, so in a call the question
/// "who is talking" was answered for a sighted viewer and not at all for a
/// screen reader user. It is also what let nothing assert, end to end, that
/// audio arrived: a ring is invisible to a test driving the semantics tree.
///
/// Driven with discrete pumps rather than `pumpAndSettle`, because the ring
/// this is about pulses forever and a tree containing one never settles.
///
/// A caller passing its own label owns the whole name and gets no suffix.
/// That is the way out for a surface borrowing the ring to mean something
/// other than speech, which `member_profile_sections.dart` does - there it
/// means "in a call with you", and inheriting "speaking" would be a claim
/// about talking that nothing has measured.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool speaking,
  String? semanticLabel,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark, AppTokens.dark),
      home: Scaffold(
        body: Center(
          child: AppAvatar(
            name: 'Ada Lovelace',
            speaking: speaking,
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    ),
  );
  // Not pumpAndSettle: a tree with a pulsing ring in it never settles.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('a speaking participant says so', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, speaking: true);
    expect(find.bySemanticsLabel('Ada Lovelace, speaking'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a quiet one is just their name', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, speaking: false);
    expect(find.bySemanticsLabel('Ada Lovelace'), findsOneWidget);
    expect(find.bySemanticsLabel('Ada Lovelace, speaking'), findsNothing);
    handle.dispose();
  });

  testWidgets('an explicit label wins outright, ring or no ring', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      speaking: true,
      semanticLabel: 'Ada Lovelace, in a call with you',
    );
    expect(
      find.bySemanticsLabel('Ada Lovelace, in a call with you'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Ada Lovelace, speaking'),
      findsNothing,
      reason: 'a surface that borrows the ring must not inherit the word',
    );
    handle.dispose();
  });
}
