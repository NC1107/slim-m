// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The call site of `AppSegmentedOption.disabled`.
///
/// `forms_test.dart` proves the component honours the flag; this proves the
/// overwrites row actually sets it. The two are separable and were: the row
/// spent a release dropping the tap in its own callback instead, which left
/// "Allow" looking and announcing as an ordinary choosable option.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/admin/permission_overwrite_row.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.light, AppTokens.light),
  home: Scaffold(body: Center(child: child)),
);

Widget _row({
  required bool allowEnabled,
  required ValueChanged<OverwriteState> onChanged,
}) => _wrap(
  PermissionOverwriteRow(
    label: 'Manage roles',
    value: OverwriteState.inherit,
    allowEnabled: allowEnabled,
    onChanged: onChanged,
  ),
);

void main() {
  testWidgets('Allow is dimmed and inert when the caller lacks the bit', (
    tester,
  ) async {
    OverwriteState? reported;
    await tester.pumpWidget(
      _row(allowEnabled: false, onChanged: (v) => reported = v),
    );

    final allow = tester.widget<Text>(find.text('Allow'));
    expect(allow.style?.color, AppTokens.light.textDisabled);

    await tester.tap(find.text('Allow'));
    await tester.pump();
    expect(reported, isNull);

    // Deny still works, so the refusal is the one option and not the row.
    await tester.tap(find.text('Deny'));
    await tester.pump();
    expect(reported, OverwriteState.deny);
  });

  testWidgets('Allow is ordinary and choosable when the caller holds it', (
    tester,
  ) async {
    OverwriteState? reported;
    await tester.pumpWidget(
      _row(allowEnabled: true, onChanged: (v) => reported = v),
    );

    final allow = tester.widget<Text>(find.text('Allow'));
    expect(allow.style?.color, isNot(AppTokens.light.textDisabled));

    await tester.tap(find.text('Allow'));
    await tester.pump();
    expect(reported, OverwriteState.allow);
  });
}
