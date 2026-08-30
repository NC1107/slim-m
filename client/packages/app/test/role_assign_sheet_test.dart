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
}
