// SPDX-License-Identifier: Apache-2.0
/// The create-channel sheet's primary button names what is missing rather
/// than sitting disabled with no explanation - the same "say why" treatment
/// `poll_composer_sheet_test.dart` already covers for its own sheet - and
/// refuses a name past the server's own 64-character ceiling before ever
/// sending it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/create_channel_sheet.dart';
import 'package:slimm_design_system/design_system.dart';

Future<void> _openSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showCreateChannelSheet(context, initialKind: 'text'),
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
  (w) => w is AppInput && w.placeholder == 'Channel name',
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

    expect(_primaryButton(tester).label, 'Add a channel name');
    expect(_primaryButton(tester).disabled, isTrue);

    await tester.enterText(_nameField(), 'announcements');
    await tester.pump();

    expect(_primaryButton(tester).label, 'Create channel');
    expect(_primaryButton(tester).disabled, isFalse);

    await tester.enterText(_nameField(), 'a' * 65);
    await tester.pump();

    expect(_primaryButton(tester).label, 'Name is too long');
    expect(_primaryButton(tester).disabled, isTrue);
  });
}
