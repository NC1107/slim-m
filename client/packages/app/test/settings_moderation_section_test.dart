// SPDX-License-Identifier: Apache-2.0
/// The settings screen's "Community management" section must be gated on
/// what `GET /me` actually reports, not shown and left to answer 403: a
/// caller with none of the four bits should see nothing new at all, and a
/// caller with one bit should see only the row that bit unlocks.
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
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/settings_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

/// Renders the settings screen with `/me` reporting [permissions], scrolled
/// down to the section under test.
///
/// A token pair is seeded because every call this screen makes, including
/// `/me`, goes through the signed session guard first: without one the client
/// refuses fast with UnauthorizedException before the mock handler ever sees
/// the request, which would make every case below read as "no permissions".
///
/// The section under test sits below several others (avatar, devices,
/// notifications, voice, presence, blocked), so the default test viewport
/// does not reach it without scrolling first. The drag is deliberately larger
/// than the list's content, matching the account-deletion test's own
/// reasoning: Flutter clamps to `maxScrollExtent` rather than erroring.
Future<ProviderContainer> _pump(WidgetTester tester, int permissions) async {
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

  // Deliberately larger than the list's content; see this function's doc.
  await tester.drag(find.byType(ListView), const Offset(0, -4000));
  await tester.pumpAndSettle();

  return container;
}

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

  testWidgets('an ordinary member with none of the four bits sees no community '
      'management section at all', (tester) async {
    await _pump(tester, 0);

    expect(find.text('Community management'), findsNothing);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('Invites'), findsNothing);
    expect(find.text('Roles'), findsNothing);
    expect(find.text('Channel permissions'), findsNothing);
  });

  testWidgets('MANAGE_MESSAGES alone unlocks only the reports row', (
    tester,
  ) async {
    await _pump(tester, Perm.manageMessages);

    expect(find.text('Community management'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Invites'), findsNothing);
    expect(find.text('Roles'), findsNothing);
    expect(find.text('Channel permissions'), findsNothing);
  });

  testWidgets('CREATE_INVITE alone unlocks only the invites row', (
    tester,
  ) async {
    await _pump(tester, Perm.createInvite);

    expect(find.text('Invites'), findsOneWidget);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('Roles'), findsNothing);
    expect(find.text('Channel permissions'), findsNothing);
  });

  testWidgets(
    'MANAGE_ROLES alone unlocks both the roles and channel permissions '
    'rows together, since one screen sets up targets the other edits',
    (tester) async {
      await _pump(tester, Perm.manageRoles);

      expect(find.text('Roles'), findsOneWidget);
      expect(find.text('Channel permissions'), findsOneWidget);
      expect(find.text('Reports'), findsNothing);
      expect(find.text('Invites'), findsNothing);
    },
  );

  /// The server resolves ADMINISTRATOR into every bit before `/me` ever
  /// answers (see `evaluate()`'s bypass in permissions.rs), so the wire value
  /// a real administrator's client receives already has every bit set; this
  /// mock mirrors that resolved value rather than sending the lone
  /// ADMINISTRATOR bit and asking the client to re-derive the bypass itself,
  /// which it deliberately does not do.
  testWidgets('an administrator sees every row', (tester) async {
    final allBits = Perm.editable.fold(0, (acc, p) => acc | p.$1);
    await _pump(tester, allBits);

    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Invites'), findsOneWidget);
    expect(find.text('Roles'), findsOneWidget);
    expect(find.text('Channel permissions'), findsOneWidget);
  });
}
