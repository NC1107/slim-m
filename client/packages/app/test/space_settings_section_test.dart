// SPDX-License-Identifier: Apache-2.0
/// `SpaceSettingsSection` and `JoinPolicyRow` used to render bare `ListTile`s,
/// whose type does not match the rest of the app (#39's reported defect).
/// Both are `AppListRow` now; this pins the row type rather than the label
/// text, since that alone would also pass against a `ListTile`.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/admin_providers.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/space_settings_section.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'admin',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

void main() {
  testWidgets('every row on Space settings is an AppListRow, never a bare '
      'ListTile', (tester) async {
    final container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
        // Every gating bit, so every row (join policy included) renders.
        myPermissionsProvider.overrideWithValue(-1),
        apiProvider.overrideWith((ref) {
          final client = api.SlimmApi(
            baseUrl: Uri.parse('http://localhost:8080'),
            session: ref.watch(sessionProvider),
            httpClient: MockClient(
              (request) async => http.Response(
                jsonEncode({'join_policy': 'invite'}),
                200,
                headers: {'content-type': 'application/json'},
              ),
            ),
          );
          ref.onDispose(client.close);
          return client;
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: const Scaffold(body: SpaceSettingsSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(ListTile),
      findsNothing,
      reason: 'a bare ListTile is the font mismatch the owner reported',
    );
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Invites'), findsOneWidget);
    expect(find.text('Roles'), findsOneWidget);
    expect(find.text('Channel permissions'), findsOneWidget);
    expect(find.text('Removed members'), findsOneWidget);
    expect(find.text('Emoji'), findsOneWidget);
    expect(find.byType(AppListRow), findsWidgets);
  });
}
