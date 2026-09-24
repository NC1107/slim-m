// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Design review note 22: the desktop title bar carries the Space's name,
/// connection dot and menu chevron now, so `RailHeader` must not draw its
/// own copy right below it while that bar is mounted - the Space named
/// twice, 40px apart, is the exact regression this covers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/desktop_window_shell.dart';
import 'package:slimm_app/src/widgets/channel_rail_frame.dart' show RailHeader;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import 'ui_snapshot_support.dart';

Future<({ProviderContainer container, SlimmDatabase db})> _pumpAtExpandedWidth(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final fixture = await fixtureContainer();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: fixture.container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        routerConfig: fixtureRouter('/channels/c-general'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

void main() {
  testWidgets('the rail header shows at expanded width with no title bar', (
    tester,
  ) async {
    final fixture = await _pumpAtExpandedWidth(tester);

    expect(find.byType(RailHeader), findsOneWidget);

    await teardownFixture(tester, fixture.container, fixture.db);
  });

  testWidgets(
    'the rail header is hidden entirely while the desktop title bar is '
    'mounted, so the Space is never named twice',
    (tester) async {
      DesktopWindowShell.debugActivate(frameless: true);
      addTearDown(DesktopWindowShell.debugReset);

      final fixture = await _pumpAtExpandedWidth(tester);

      expect(find.byType(RailHeader), findsNothing);

      await teardownFixture(tester, fixture.container, fixture.db);
    },
  );
}
