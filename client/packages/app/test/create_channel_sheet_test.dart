// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The create-channel sheet's primary button names what is missing rather
/// than sitting disabled with no explanation - the same "say why" treatment
/// `poll_composer_sheet_test.dart` already covers for its own sheet - and
/// refuses a name past the server's own 64-character ceiling before ever
/// sending it.
///
/// The Private toggle is absent rather than disabled for a caller without
/// MANAGE_ROLES, the same convention `channel_settings_screen_test.dart`
/// covers for its own MANAGE_ROLES-gated section.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/permissions.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/create_channel_sheet.dart';
import 'package:slimm_design_system/design_system.dart';

Future<void> _openSheet(WidgetTester tester, {int permissions = 0}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        meProvider.overrideWith(
          (ref) async => api.Me(
            id: 'user-1',
            username: 'user-1',
            displayName: 'User',
            createdAt: 0,
            permissions: permissions,
          ),
        ),
      ],
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

Finder _privateToggle() => find.byWidgetPredicate(
  (w) => w is AppToggle && w.semanticLabel == 'Make this channel private',
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

  testWidgets('the Private toggle is absent without MANAGE_ROLES', (
    tester,
  ) async {
    await _openSheet(tester, permissions: 0);

    expect(_privateToggle(), findsNothing);
  });

  testWidgets(
    'the Private toggle appears, defaults off, and can be switched on for a '
    'MANAGE_ROLES holder',
    (tester) async {
      await _openSheet(tester, permissions: Perm.manageRoles);

      expect(_privateToggle(), findsOneWidget);
      expect(tester.widget<AppToggle>(_privateToggle()).value, isFalse);

      await tester.tap(_privateToggle());
      await tester.pump();

      expect(tester.widget<AppToggle>(_privateToggle()).value, isTrue);
    },
  );
}
