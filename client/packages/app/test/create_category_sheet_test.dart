// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/create_category_sheet.dart';
import 'package:slimm_design_system/design_system.dart';

Future<void> _openSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCreateCategorySheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _nameField() => find.byWidgetPredicate(
  (w) => w is AppInput && w.placeholder == 'Category name',
);

AppButton _primaryButton(WidgetTester tester) => tester.widget<AppButton>(
  find.byWidgetPredicate(
    (w) => w is AppButton && w.variant == AppButtonVariant.primary,
  ),
);

void main() {
  testWidgets('names what is missing rather than sitting disabled mute', (
    tester,
  ) async {
    await _openSheet(tester);

    expect(_primaryButton(tester).label, 'Add a category name');
    expect(_primaryButton(tester).disabled, isTrue);

    await tester.enterText(_nameField(), 'Projects');
    await tester.pump();

    expect(_primaryButton(tester).label, 'Create category');
    expect(_primaryButton(tester).disabled, isFalse);

    // The server refuses past 64; say so here rather than after a round trip.
    await tester.enterText(_nameField(), 'a' * 65);
    await tester.pump();

    expect(_primaryButton(tester).label, 'Name is too long');
    expect(_primaryButton(tester).disabled, isTrue);
  });
}
