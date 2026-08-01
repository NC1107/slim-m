// SPDX-License-Identifier: Apache-2.0
/// The gate is how the sheet is actually reached: no route is registered for
/// it (see the widget's own doc comment on why `route_reachability_test.dart`
/// does not need one), so this is what proves a real user sees it, rather
/// than only proving the controller's state transitions in isolation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/whats_new_controller.dart';
import 'package:slimm_app/src/widgets/whats_new_gate.dart';
import 'package:slimm_design_system/design_system.dart';

Future<ProviderContainer> _pumpGate(
  WidgetTester tester, {
  required bool fresh,
}) async {
  final container = ProviderContainer(
    overrides: [isFreshInstallProvider.overrideWith((ref) => fresh)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const WhatsNewGate(child: Scaffold(body: SizedBox())),
      ),
    ),
  );
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'slim-m',
      packageName: 'top.npcserver.slimm',
      version: '0.17.2',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    'an existing install with nothing recorded sees the sheet, including '
    'the reconciliation notice',
    (tester) async {
      await _pumpGate(tester, fresh: false);
      // One pump for the async check, one for its post-frame callback.
      await tester.pump();
      await tester.pump();

      expect(find.text("What's new"), findsOneWidget);
      expect(
        find.textContaining('newest 50 messages'),
        findsOneWidget,
        reason:
            'the message-reconciliation entry must actually reach an '
            'upgrading install, not just exist in the source',
      );
    },
  );

  testWidgets('a fresh install never sees the sheet', (tester) async {
    final container = await _pumpGate(tester, fresh: true);
    await tester.pumpAndSettle();

    expect(find.text("What's new"), findsNothing);
    expect(container.read(whatsNewControllerProvider), isEmpty);
  });

  testWidgets('dismissing the sheet marks it seen, so it does not reappear', (
    tester,
  ) async {
    final container = await _pumpGate(tester, fresh: false);
    await tester.pump();
    await tester.pump();
    expect(find.text("What's new"), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, 'Got it'));
    await tester.pumpAndSettle();

    expect(find.text("What's new"), findsNothing);
    expect(container.read(whatsNewControllerProvider), isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(lastSeenWhatsNewVersionKey), '0.17.2');
  });
}
