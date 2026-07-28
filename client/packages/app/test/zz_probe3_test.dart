// SPDX-License-Identifier: Apache-2.0
/// Temporary probe: enumerate the GestureDetector ancestors of the Allow text.
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
  testWidgets('enumerate', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PermissionOverwriteRow(
          label: 'Manage roles',
          value: OverwriteState.inherit,
          allowEnabled: false,
          onChanged: (_) {},
        ),
      ),
    );

    final all = find
        .ancestor(
          of: find.text('Allow'),
          matching: find.byType(GestureDetector),
        )
        .evaluate()
        .toList();
    debugPrint('GD ancestors of Allow: ${all.length}');
    for (final e in all) {
      final gd = e.widget as GestureDetector;
      debugPrint('  onTap=${gd.onTap} behavior=${gd.behavior}');
    }

    final sem = find
        .ancestor(
          of: find.text('Allow'),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Allow',
          ),
        )
        .evaluate()
        .toList();
    debugPrint('Semantics(label=Allow) ancestors: ${sem.length}');
    for (final e in sem) {
      final s = e.widget as Semantics;
      debugPrint(
        '  enabled=${s.properties.enabled} onTap=${s.properties.onTap}',
      );
    }

    debugPrint(
      'Allow text color: ${tester.widget<Text>(find.text('Allow')).style?.color}',
    );
  });
}
