// SPDX-License-Identifier: Apache-2.0
/// Tests for the settings screen's account actions: a failure partway
/// through sign-out or deletion must reach the screen, not vanish and leave
/// the user stranded.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/settings_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'slim-m',
      packageName: 'top.npcserver.slimm',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
      'a failed account deletion is shown on screen, not silently left '
      'signed in with sync already stopped and the push key already gone',
      (tester) async {
    // Signed out, so deleteAccount() (like every other authenticated call
    // this screen makes) fails fast with UnauthorizedException before any
    // request is sent; the point under test is that the failure reaches the
    // screen instead of disappearing into an unhandled Future.
    final container = ProviderContainer(overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient:
              MockClient((_) async => throw StateError('unexpected call')),
        );
        ref.onDispose(api.close);
        return api;
      }),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Below the fold on the default test viewport; the account section is
    // last in the list. ListView builds every child eagerly, so the finder
    // already resolves before any scrolling; drag directly rather than via
    // scrollUntilVisible, which only scrolls until the finder resolves at
    // all, not until the target is actually within the viewport.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not delete the account'),
      findsOneWidget,
    );
  });
}
