// SPDX-License-Identifier: Apache-2.0
/// The three ways this sheet differs from `role_assign_sheet.dart`, each of
/// which is a real bug if the symmetric version is copied across.
///
/// The duplicate-name case is the one worth the most: with a role fixed, two
/// roles called "mod" mis-render one column, but with a *member* fixed they
/// light up every row sharing the name - so somebody reading a moderator's
/// assignments is told they hold a role they do not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/permissions.dart';
import 'package:slimm_app/src/providers/admin_providers.dart';
import 'package:slimm_app/src/providers/member_presence.dart';
import 'package:slimm_app/src/widgets/member_roles_sheet.dart';
import 'package:slimm_design_system/design_system.dart';

api.Role _role(
  String id,
  String name,
  int permissions, {
  bool everyone = false,
}) => api.Role(
  id: id,
  name: name,
  permissions: permissions,
  isEveryone: everyone,
  createdAt: 0,
);

const _memberId = 'user-maya';

api.UserProfile _member(List<String> roleIds, List<String> roleNames) =>
    api.UserProfile(
      id: _memberId,
      username: 'maya',
      displayName: 'maya',
      createdAt: 0,
      roles: roleNames,
      roleIds: roleIds,
    );

Widget _harness({
  required List<api.Role> roles,
  required api.UserProfile member,
  int permissions = Perm.administrator,
}) => ProviderScope(
  overrides: [
    myPermissionsProvider.overrideWithValue(permissions),
    rolesProvider.overrideWith((ref) async => roles),
    membersProvider.overrideWith((ref) async => [member]),
  ],
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: const Scaffold(body: MemberRolesSheet(userId: _memberId)),
  ),
);

AppToggle _toggleFor(WidgetTester tester, String roleName) {
  final row = find.ancestor(
    of: find.text(roleName),
    matching: find.byType(AppListRow),
  );
  return tester.widget<AppToggle>(
    find.descendant(of: row, matching: find.byType(AppToggle)),
  );
}

void main() {
  testWidgets('@everyone is never offered as something to grant', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        roles: [
          _role('role-everyone', '@everyone', Perm.viewChannel, everyone: true),
          _role('role-mod', 'mod', Perm.manageMessages),
        ],
        member: _member(const ['role-mod'], const ['mod']),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('mod'), findsOneWidget);
    expect(
      find.text('@everyone'),
      findsNothing,
      reason:
          'every member holds it, the server strips it from a profile, '
          'and the assign route has no guard - so its toggle would read off '
          'forever and could not be switched back',
    );
  });

  testWidgets('a role is held by id, never by the name beside it', (
    tester,
  ) async {
    // Two roles, same name. Only the second is actually assigned.
    await tester.pumpWidget(
      _harness(
        roles: [
          _role('role-mod-a', 'mod', Perm.manageMessages),
          _role('role-mod-b', 'mod', Perm.kickMembers),
        ],
        member: _member(const ['role-mod-b'], const ['mod']),
      ),
    );
    await tester.pumpAndSettle();

    final toggles = tester
        .widgetList<AppToggle>(find.byType(AppToggle))
        .toList();
    expect(toggles.length, 2);
    expect(
      toggles.where((t) => t.value).length,
      1,
      reason: 'matching by name would light up both rows',
    );
  });

  testWidgets('a role you cannot grant is shown disabled, never hidden', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        roles: [
          _role('role-admin', 'admin', Perm.administrator),
          _role('role-mod', 'mod', Perm.manageMessages),
        ],
        // The member holds the one this caller cannot hand out.
        member: _member(const ['role-admin'], const ['admin']),
        permissions: Perm.manageRoles | Perm.manageMessages,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('admin'),
      findsOneWidget,
      reason: 'hiding it would under-report this member to the moderator',
    );
    expect(find.text('Needs permissions you do not hold'), findsOneWidget);

    final admin = _toggleFor(tester, 'admin');
    expect(admin.value, isTrue, reason: 'they really do hold it');
    expect(
      admin.onChanged,
      isNull,
      reason:
          'the server refuses to hand out a bit the caller lacks, so the '
          'toggle must not move and spring back',
    );

    expect(_toggleFor(tester, 'mod').onChanged, isNotNull);
  });

  testWidgets('a Space with only @everyone says so rather than showing blank', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        roles: [
          _role('role-everyone', '@everyone', Perm.viewChannel, everyone: true),
        ],
        member: _member(const [], const []),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('no roles beyond @everyone'), findsOneWidget);
  });
}
