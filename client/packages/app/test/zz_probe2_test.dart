// SPDX-License-Identifier: Apache-2.0
/// Temporary probe: a non-vacuous form of the proposed app-level test.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/admin/permission_overwrite_row.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.light, AppTokens.light),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('Allow is presented as unavailable when the bit is not held', (
    tester,
  ) async {
    OverwriteState? reported;
    await tester.pumpWidget(
      _wrap(
        PermissionOverwriteRow(
          label: 'Manage roles',
          value: OverwriteState.inherit,
          allowEnabled: false,
          onChanged: (v) => reported = v,
        ),
      ),
    );

    final allow = tester.widget<GestureDetector>(
      find.ancestor(
        of: find.text('Allow'),
        matching: find.byType(GestureDetector),
      ),
    );
    expect(allow.onTap, isNull);

    await tester.tap(find.text('Deny'));
    await tester.pump();
    expect(reported, OverwriteState.deny);
  });
}
