// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A sheet paints the app's own raised surface in both of its shapes.
///
/// `showAppSheet` renders a dialog on a desktop and a bottom sheet on a
/// phone. The dialog always painted `AppTokens.surfaceRaised` explicitly; the
/// bottom sheet passed no colour at all, so Material fell back to its own
/// generated `surfaceContainerLow`. The same sheet, with the same content,
/// was a different colour on a phone than on a desktop, and the strip the
/// sheet reserves for the home indicator read as a seam under the last row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Future<Color?> _sheetSurface(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark, AppTokens.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showAppSheet<void>(
                context,
                builder: (_) =>
                    const SizedBox(height: 120, child: Text('body')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  final material = tester
      .widgetList<Material>(
        find.ancestor(of: find.text('body'), matching: find.byType(Material)),
      )
      .firstWhere((m) => m.color != null);
  return material.color;
}

void main() {
  testWidgets('a phone sheet and a desktop dialog paint the same surface', (
    tester,
  ) async {
    final phone = await _sheetSurface(tester, 390);
    expect(phone, AppTokens.dark.surfaceRaised);
  });

  testWidgets('the desktop dialog paints it too', (tester) async {
    final desktop = await _sheetSurface(tester, 1200);
    expect(desktop, AppTokens.dark.surfaceRaised);
  });
}
