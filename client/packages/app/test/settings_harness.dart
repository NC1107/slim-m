// SPDX-License-Identifier: Apache-2.0
/// Shared fixtures for the two suites that pump the whole settings screen:
/// the Space group's permission gating, and the taxonomy the three group
/// headers impose on it.
///
/// Not a `_test.dart` file, so `flutter test` does not try to run it. It
/// exists because both suites need the same signed-in session, the same `/me`
/// permission answer and the same stubbed device and block lists, none of
/// which either suite is actually about.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/permissions.dart';
import 'package:slimm_app/src/screens/settings_screen.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

/// Every permission bit the client knows how to name, which is what the
/// server sends a real administrator: `evaluate()`'s ADMINISTRATOR bypass is
/// resolved before `/me` answers, so the wire value already has them all.
int get allPermissionBits => Perm.editable.fold(0, (acc, p) => acc | p.$1);

/// The build identity `_AppSection` reads. Called from `setUpAll`, since
/// `PackageInfo` otherwise throws on a test binding with no host platform.
void mockAppVersion() {
  PackageInfo.setMockInitialValues(
    appName: 'slim-m',
    packageName: 'top.npcserver.slimm',
    version: '0.1.0',
    buildNumber: '1',
    buildSignature: '',
  );
}

/// Renders the settings screen with `/me` reporting [permissions], scrolled
/// down to the section under test.
///
/// A token pair is seeded because every call this screen makes, including
/// `/me`, goes through the signed session guard first: without one the client
/// refuses fast with UnauthorizedException before the mock handler ever sees
/// the request, which would make every case read as "no permissions".
///
/// The Space and App groups sit below the whole personal half (avatar,
/// appearance, presence, notifications, voice, devices, blocked, account), so
/// the default test viewport does not reach them without scrolling first. The
/// drag is deliberately larger than the list's content, matching the
/// account-deletion test's own reasoning: Flutter clamps to
/// `maxScrollExtent` rather than erroring.
Future<ProviderContainer> pumpSettings(
  WidgetTester tester,
  int permissions, {
  bool scrollToBottom = true,
}) async {
  const tokens = TokenPair(
    userId: 'self',
    accessToken: 'access',
    refreshToken: 'refresh',
    accessExpiresAt: 0,
  );
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(SessionStore(tokens: tokens)),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            if (request.url.path == '/devices' ||
                request.url.path == '/blocks') {
              return http.Response(
                '[]',
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.path == '/me') {
              return http.Response(
                jsonEncode({
                  'id': 'self',
                  'username': 'self',
                  'display_name': 'Self',
                  'created_at': 0,
                  'permissions': permissions,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              '{}',
              404,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        ref.onDispose(api.close);
        return api;
      }),
    ],
  );
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

  if (scrollToBottom) {
    // Deliberately larger than the list's content; see this function's doc.
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();
  }

  return container;
}

/// A viewport tall enough to hold the whole settings list at once, so every
/// group header is built and their positions are comparable without scrolling
/// any of them out of the tree.
void useTallViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 2400);
  addTearDown(tester.view.reset);
}
