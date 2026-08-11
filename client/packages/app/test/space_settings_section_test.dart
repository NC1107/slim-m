// SPDX-License-Identifier: Apache-2.0
/// `SpaceSettingsSection` and `JoinPolicyRow` used to render bare `ListTile`s,
/// whose type does not match the rest of the app (#39's reported defect).
/// Both are `AppListRow` now; this pins the row type rather than the label
/// text, since that alone would also pass against a `ListTile`.
///
/// The rows also used to sit in one flat column with no header or border,
/// which read as a different app from personal settings' bordered
/// `SettingsSectionCard` groups (#63's reported defect). The tests below pin
/// that grouping rather than the row type, since a flat column of the same
/// `AppListRow`s would still pass every test above.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/permissions.dart';
import 'package:slimm_app/src/providers/admin_providers.dart';
import 'package:slimm_app/src/providers/channel_permissions.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/settings_notice.dart';
import 'package:slimm_app/src/widgets/space_settings_section.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'admin',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

ProviderContainer _container(int permissions) => ProviderContainer(
  overrides: [
    keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
    sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
    myPermissionsProvider.overrideWithValue(permissions),
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

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
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
}

void main() {
  testWidgets('every row on Space settings is an AppListRow, never a bare '
      'ListTile', (tester) async {
    // Every gating bit, so every row (join policy included) renders.
    await _pump(tester, _container(-1));

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

  testWidgets(
    'rows sit in bordered SettingsSectionCard groups, matching personal '
    'settings, not a flat column under the app bar',
    (tester) async {
      await _pump(tester, _container(-1));

      // One AppCard per non-empty group (Moderation, Access, Configuration).
      expect(find.byType(AppCard), findsNWidgets(3));
      expect(find.text('Moderation'), findsOneWidget);
      expect(find.text('Access'), findsOneWidget);
      expect(find.text('Configuration'), findsOneWidget);
    },
  );

  testWidgets(
    'a group with none of its rows visible renders no header at all, rather '
    'than an empty card',
    (tester) async {
      // CREATE_INVITE alone: only the Access group has anything in it.
      await _pump(tester, _container(Perm.createInvite));

      expect(find.text('Access'), findsOneWidget);
      expect(find.text('Invites'), findsOneWidget);
      expect(
        find.text('Moderation'),
        findsNothing,
        reason: 'Reports and Removed members are both hidden here',
      );
      expect(
        find.text('Configuration'),
        findsNothing,
        reason: 'Roles, permissions, categories and emoji are all hidden',
      );
      expect(find.byType(AppCard), findsOneWidget);
    },
  );

  testWidgets(
    'Channel permissions alone opens for MANAGE_ROLES held only through one '
    "visible channel's overwrite, with Roles itself staying hidden",
    (tester) async {
      // Base is CREATE_INVITE alone, so only the channel can explain the row.
      final container = ProviderContainer(
        overrides: [
          keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
          sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
          myPermissionsProvider.overrideWithValue(Perm.createInvite),
          myVisibleChannelsProvider.overrideWith(
            (ref) async => const [
              api.Channel(
                id: 'c1',
                name: 'general',
                kind: 'text',
                createdAt: 0,
                permissions: Perm.manageRoles,
              ),
            ],
          ),
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
      await _pump(tester, container);

      expect(find.text('Channel permissions'), findsOneWidget);
      expect(
        find.text('Roles'),
        findsNothing,
        reason:
            'role CRUD is deployment-wide; a channel overwrite grants '
            'nothing towards it',
      );
    },
  );

  testWidgets('a caller holding none of the gating bits gets a stated reason, '
      'not a blank page', (tester) async {
    await _pump(tester, _container(0));

    expect(
      find.byType(SettingsNotice),
      findsOneWidget,
      reason:
          'this widget is SpaceSettingsScreen\'s entire body, so returning '
          'SizedBox.shrink() rendered a bare app bar over blank white. The '
          'path that matters is not a stray URL: this watches '
          'myPermissionsProvider, so a member demoted while the screen is '
          'open watches it collapse to that blank page.',
    );
    expect(
      find.textContaining('None of your roles grant access'),
      findsOneWidget,
    );
    expect(
      find.byType(AppCard),
      findsNothing,
      reason: 'nothing is reachable, so no group should render',
    );
  });

  testWidgets('the notice states what would put something here', (
    tester,
  ) async {
    await _pump(tester, _container(0));

    expect(
      find.textContaining('An administrator can grant you one of those'),
      findsOneWidget,
      reason:
          'a stated absence that does not say what would change it is only '
          'half the fix',
    );
  });
}
