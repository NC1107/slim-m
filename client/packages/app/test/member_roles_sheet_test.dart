// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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

  // The owner: "very ugly role menu" - the card must actually be inset, not merely present, at both a phone and a desktop width.
  for (final width in [390.0, 900.0]) {
    testWidgets(
      'at ${width.toInt()}px, with a single role the row sits inside a '
      'card inset from the sheet edges rather than touching them',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _harness(
            roles: [_role('role-mod', 'mod', Perm.manageMessages)],
            member: _member(const ['role-mod'], const ['mod']),
          ),
        );
        await tester.pumpAndSettle();

        final sheet = tester.getRect(find.byType(MemberRolesSheet));
        final card = tester.getRect(find.byKey(memberRolesListBoxKey));

        expect(
          card.left - sheet.left,
          AppSpacing.s16,
          reason:
              'the card must sit off the sheet edge like the title above it',
        );
        expect(
          sheet.right - card.right,
          AppSpacing.s16,
          reason: 'same inset on the trailing edge',
        );
        expect(
          sheet.bottom - card.bottom,
          greaterThanOrEqualTo(AppSpacing.s16),
          reason: 'the row must not touch the sheet\'s own bottom edge either',
        );
      },
    );
  }

  // "Design for one role and for fifteen": grouping has to scale, not just look deliberate for the one-row case the owner's screenshot showed.
  testWidgets(
    'with many roles, each one is set apart by a real divider, not just '
    'stacked bare rows',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const count = 15;
      await tester.pumpWidget(
        _harness(
          roles: [
            for (var i = 0; i < count; i++) _role('role-$i', 'role-$i', 0),
          ],
          member: _member(const [], const []),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppListRow), findsNWidgets(count));
      expect(
        find.byType(Divider),
        findsNWidgets(count - 1),
        reason: 'one separator between each pair of rows, none at the ends',
      );
    },
  );

  /// overlays.md: this sheet forced a fixed `height * 0.7` regardless of row
  /// count, leaving most of the card empty for two roles. It must now size
  /// to its content, which a `shrinkWrap` `ListView` inside a `maxHeight`
  /// ceiling is what makes possible.
  testWidgets('a short role list does not force the sheet to a fixed height', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        roles: [_role('role-mod', 'mod', Perm.manageMessages)],
        member: _member(const ['role-mod'], const ['mod']),
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(
      list.shrinkWrap,
      isTrue,
      reason:
          'without this the list always claims its full maxHeight '
          'ceiling regardless of how few rows it holds',
    );

    final sheetHeight = tester.getSize(find.byType(MemberRolesSheet)).height;
    final windowHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      sheetHeight,
      lessThan(windowHeight * 0.3),
      reason:
          'one role row plus a heading must read as itself, not as a '
          'card mostly empty below it',
    );
  });
}
