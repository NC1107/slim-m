// SPDX-License-Identifier: Apache-2.0
/// The settings screen's "Space" group must be gated on what `GET /me`
/// actually reports, not shown and left to answer 403: a caller with none of
/// the gating bits should see no Space group at all, and a caller with one
/// bit should see only the row that bit unlocks.
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
/// The group under test sits below the whole personal half (avatar,
/// appearance, presence, notifications, voice, devices, blocked, account),
/// so the default test viewport
/// does not reach it without scrolling first. The drag is deliberately larger
/// than the list's content, matching the account-deletion test's own
/// reasoning: Flutter clamps to `maxScrollExtent` rather than erroring.
Future<ProviderContainer> _pump(
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

  /// The split is the feature, not just the gating: everything personal has
  /// to sit under "Personal" and everything about the deployment under
  /// "Space", in that order, or the two are one undifferentiated list again.
  ///
  /// A viewport tall enough to hold the whole list, so both headers are built
  /// and their positions comparable without scrolling either out of the tree.
  testWidgets('an administrator sees the personal half and the Space half as '
      'two named groups, personal first', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 2400);
    addTearDown(tester.view.reset);

    final allBits = Perm.editable.fold(0, (acc, p) => acc | p.$1);
    await _pump(tester, allBits, scrollToBottom: false);

    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Space'), findsOneWidget);

    final personal = tester.getRect(find.text('Personal')).top;
    final space = tester.getRect(find.text('Space')).top;
    expect(personal, lessThan(space));

    // Every personal section sits between the two headers, so nothing
    // personal has drifted under "Space".
    for (final section in const [
      'Avatar',
      'Appearance',
      'Presence',
      'Notifications',
      'Voice',
      'Devices',
      'Blocked',
      'Account',
    ]) {
      final top = tester.getRect(find.text(section)).top;
      expect(
        top,
        inExclusiveRange(personal, space),
        reason: '$section is not inside the Personal group',
      );
    }

    // And every Space row sits after the "Space" header.
    for (final row in const [
      'Reports',
      'Invites',
      'Roles',
      'Channel permissions',
      'Emoji',
    ]) {
      expect(
        tester.getRect(find.text(row)).top,
        greaterThan(space),
        reason: '$row is not inside the Space group',
      );
    }
  });

  testWidgets('an ordinary member with none of the gating bits sees no '
      'Space group at all', (tester) async {
    await _pump(tester, 0);

    expect(find.text('Space'), findsNothing);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('Invites'), findsNothing);
    expect(find.text('Roles'), findsNothing);
    expect(find.text('Channel permissions'), findsNothing);
    expect(find.text('Emoji'), findsNothing);
  });

  testWidgets('MANAGE_MESSAGES alone unlocks only the reports row', (
    tester,
  ) async {
    await _pump(tester, Perm.manageMessages);

    expect(find.text('Space'), findsOneWidget);
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

  /// MANAGE_SERVER is the bit the emoji endpoints themselves enforce
  /// (`require_manage_server` in `crates/slimm-server/src/http/emoji.rs`), so
  /// it is the bit the row is gated on. It unlocks nothing else: a caller who
  /// can change what the deployment is cannot thereby read the report queue.
  testWidgets('MANAGE_SERVER alone unlocks only the emoji row', (tester) async {
    await _pump(tester, Perm.manageServer);

    expect(find.text('Space'), findsOneWidget);
    expect(find.text('Emoji'), findsOneWidget);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('Invites'), findsNothing);
    expect(find.text('Roles'), findsNothing);
    expect(find.text('Channel permissions'), findsNothing);
  });

  testWidgets('MANAGE_ROLES does not bring the emoji row with it', (
    tester,
  ) async {
    await _pump(tester, Perm.manageRoles);

    expect(find.text('Emoji'), findsNothing);
  });

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
    expect(find.text('Emoji'), findsOneWidget);
  });
}
