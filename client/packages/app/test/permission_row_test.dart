// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The row the two permission screens share, and the role editor's use of it.
///
/// The role editor and the channel overwrite screen both set permissions on
/// something, and each used to own a row widget of its own: two paddings, two
/// label treatments, no shared shape. Somebody who learned one screen did not
/// recognise the other. They now render one [PermissionRow] with a different
/// control in it, and these tests pin the parts that must not diverge again.
///
/// The role editor sheet had no behavioural test at all before this - only a
/// snapshot surface - so the dimming rule is covered here too: a permission the
/// caller does not hold themselves is shown dimmed and its toggle does nothing,
/// because the server refuses to grant a bit the granter lacks.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/permissions.dart';
import 'package:slimm_app/src/providers/admin_providers.dart';
import 'package:slimm_app/src/screens/admin/permission_overwrite_row.dart';
import 'package:slimm_app/src/screens/admin/role_editor_sheet.dart';
import 'package:slimm_app/src/widgets/permission_row.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.light, AppTokens.light),
  home: Scaffold(body: Center(child: child)),
);

EdgeInsets _rowPadding(WidgetTester tester) {
  final padding = tester.widget<Padding>(
    find
        .descendant(
          of: find.byType(PermissionRow),
          matching: find.byType(Padding),
        )
        .first,
  );
  return padding.padding.resolve(TextDirection.ltr);
}

void main() {
  testWidgets('both controls sit in the same row chrome', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PermissionRow(
          label: 'Manage roles',
          control: AppToggle(
            value: true,
            semanticLabel: 'Manage roles',
            onChanged: (_) {},
          ),
        ),
      ),
    );
    final inline = _rowPadding(tester);
    final inlineLabel = tester.getTopLeft(find.text('Manage roles'));

    await tester.pumpWidget(
      _wrap(
        const PermissionOverwriteRow(
          label: 'Manage roles',
          value: OverwriteState.inherit,
          allowEnabled: true,
          onChanged: _ignore,
        ),
      ),
    );
    expect(
      find.byType(PermissionRow),
      findsOneWidget,
      reason: 'the overwrite row must render through the shared chrome',
    );
    expect(
      _rowPadding(tester),
      inline,
      reason: 'a row is the same height whichever control it holds',
    );
    expect(
      tester.getTopLeft(find.text('Manage roles')).dx,
      inlineLabel.dx,
      reason: 'and the label starts in the same place',
    );
  });

  testWidgets('the role editor dims a permission the caller lacks', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [myPermissionsProvider.overrideWithValue(Perm.manageRoles)],
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRoleEditorSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final rows = tester.widgetList<PermissionRow>(find.byType(PermissionRow));
    expect(
      rows,
      isNotEmpty,
      reason: 'the role editor must use the shared row, not one of its own',
    );

    final held = rows.firstWhere((r) => r.label == 'Manage roles');
    final notHeld = rows.firstWhere((r) => r.label == 'Ban members');
    expect(
      held.dimmed,
      isFalse,
      reason: 'a permission the caller holds reads normally',
    );
    expect(
      notHeld.dimmed,
      isTrue,
      reason:
          'the server refuses granting a bit the granter lacks, so the row '
          'must not look available',
    );
    expect(
      (notHeld.control as AppToggle).onChanged,
      isNull,
      reason: 'and it must be inert, not merely dim',
    );
  });
}

void _ignore(OverwriteState _) {}
