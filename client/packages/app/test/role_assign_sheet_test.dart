// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Tests that this sheet does not offer a grant the server will refuse.
///
/// The server enforces permission containment: a caller may only hand out a
/// role whose permissions they already hold themselves. This sheet used to
/// offer every toggle regardless of that, so a caller with MANAGE_ROLES but
/// not ADMINISTRATOR could flip an admin role's toggle and get a 403 back
/// with no warning. `member_roles_sheet.dart` already gets this right; the
/// fix here copies its pattern rather than inventing a second one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/permissions.dart';
import 'package:slimm_app/src/providers/admin_providers.dart';
import 'package:slimm_app/src/providers/member_presence.dart';
import 'package:slimm_app/src/screens/admin/role_assign_sheet.dart';
import 'package:slimm_design_system/design_system.dart';

api.Role _role(String id, String name, int permissions) => api.Role(
  id: id,
  name: name,
  permissions: permissions,
  isEveryone: false,
  createdAt: 0,
);

api.UserProfile _member(String id, String name) =>
    api.UserProfile(id: id, username: name, displayName: name, createdAt: 0);

Future<void> _pumpSheet(
  WidgetTester tester, {
  required api.Role role,
  required int permissions,
  Future<List<api.UserProfile>> Function(Ref ref)? members,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myPermissionsProvider.overrideWithValue(permissions),
        membersProvider.overrideWith(
          members ?? (ref) async => [_member('u1', 'maya')],
        ),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRoleAssignSheet(context, role),
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

void main() {
  testWidgets(
    'a role carrying a permission the caller lacks is disabled with the '
    'meta line',
    (tester) async {
      await _pumpSheet(
        tester,
        role: _role('role-admin', 'admin', Perm.administrator),
        permissions: Perm.manageRoles,
      );

      expect(find.text('Needs permissions you do not hold'), findsOneWidget);
      final toggle = tester.widget<AppToggle>(find.byType(AppToggle));
      expect(
        toggle.onChanged,
        isNull,
        reason:
            'the server refuses this grant, so the toggle must not move '
            'and spring back',
      );
    },
  );

  testWidgets('a role the caller already holds is not disabled', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      role: _role('role-mod', 'mod', Perm.manageMessages),
      permissions: Perm.manageRoles | Perm.manageMessages,
    );

    expect(find.text('Needs permissions you do not hold'), findsNothing);
    final toggle = tester.widget<AppToggle>(find.byType(AppToggle));
    expect(toggle.onChanged, isNotNull);
  });

  testWidgets(
    'a failed member fetch offers a retry, which refetches - this sheet was '
    'the one AppAsyncView holdout whose failure had no way back',
    (tester) async {
      var fetches = 0;
      await _pumpSheet(
        tester,
        role: _role('role-mod', 'mod', Perm.manageMessages),
        permissions: Perm.manageRoles | Perm.manageMessages,
        members: (ref) async {
          fetches++;
          if (fetches == 1) throw Exception('boom');
          return [_member('u1', 'maya')];
        },
      );

      expect(find.text('Could not load members.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(fetches, 2);
      expect(find.byType(AppToggle), findsOneWidget);
    },
  );

  // Previously this sheet had no isEmpty/emptyMessage at all, unlike member_roles_sheet.dart's own version of it - an empty roster rendered blank.
  testWidgets(
    'a Space with no members to assign says so rather than showing blank',
    (tester) async {
      await _pumpSheet(
        tester,
        role: _role('role-mod', 'mod', Perm.manageMessages),
        permissions: Perm.manageRoles,
        members: (ref) async => [],
      );

      expect(find.textContaining('no members'), findsOneWidget);
    },
  );

  // The owner: "very ugly role menu" - the card must be inset on the desktop dialog `showAppSheet` renders at this window width.
  testWidgets('on a desktop window, the row sits inside a card inset from the '
      'dialog edges rather than touching them', (tester) async {
    await _pumpSheet(
      tester,
      role: _role('role-mod', 'mod', Perm.manageMessages),
      permissions: Perm.manageRoles,
    );

    final sheet = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is ConstrainedBox && w.constraints.maxWidth == kSheetMaxWidth,
      ),
    );
    final card = tester.getRect(find.byKey(roleAssignBodyBoxKey));

    expect(
      card.left - sheet.left,
      AppSpacing.s16,
      reason: 'the card must sit off the sheet edge like the title above it',
    );
    expect(
      sheet.right - card.right,
      AppSpacing.s16,
      reason: 'same inset on the trailing edge',
    );
  });

  // Below kCompactWidth, showAppSheet renders a full-width bottom sheet: the same inset holds against the screen edge, not a ConstrainedBox.
  testWidgets(
    'on a phone window, the row sits inside a card inset from the sheet '
    'edges rather than touching them',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpSheet(
        tester,
        role: _role('role-mod', 'mod', Perm.manageMessages),
        permissions: Perm.manageRoles,
      );

      final windowWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final card = tester.getRect(find.byKey(roleAssignBodyBoxKey));

      expect(
        card.left,
        AppSpacing.s16,
        reason: 'the card must sit off the screen edge like the title above it',
      );
      expect(
        windowWidth - card.right,
        AppSpacing.s16,
        reason: 'same inset on the trailing edge',
      );
    },
  );
}
