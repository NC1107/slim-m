// SPDX-License-Identifier: Apache-2.0
/// Tests for the personal space row's own kebab: it opens a menu with one
/// action, that action hides the row, and hiding it says how to get it
/// back rather than vanishing silently.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/dms.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/channel_rail_sections.dart';
import 'package:slimm_app/src/widgets/personal_space_menu.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

ProviderContainer _container() => ProviderContainer(
  overrides: [
    keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
    sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
    databaseProvider.overrideWith((ref) async {
      final db = SlimmDatabase(NativeDatabase.memory());
      ref.onDispose(db.close);
      return db;
    }),
    apiProvider.overrideWith((ref) {
      final client = api.SlimmApi(
        baseUrl: Uri.parse('http://localhost:8080'),
        session: ref.watch(sessionProvider),
        httpClient: MockClient(
          (request) async => throw StateError(
            'unexpected request in this test: ${request.url}',
          ),
        ),
      );
      ref.onDispose(client.close);
      return client;
    }),
  ],
);

Widget _harness(ProviderContainer container, List<Channel> channels) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          body: DirectMessagesSection(channels: channels, selectedId: null),
        ),
      ),
    );

const _personal = Channel(
  id: 'dm-self',
  name: personalSpaceName,
  kind: dmChannelKind,
  createdAt: 0,
  cursor: 0,
  lastReadSeq: 0,
  isPersonalSpace: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('an existing personal space carries a kebab with one action', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container, [_personal]));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Personal space options'));
    await tester.pumpAndSettle();

    expect(find.text('Remove from list'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a personal space that has never been opened carries no kebab at all',
    (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container, const []));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Personal space options'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'choosing "Remove from list" hides the row and names the way back',
    (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container, [_personal]));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Personal space options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from list'));
      await tester.pumpAndSettle();

      expect(
        find.text(personalSpaceName),
        findsNothing,
        reason: 'the row itself must be gone, not merely its menu closed',
      );
      expect(find.text(personalSpaceHiddenNotice), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'the hidden flag is keyed by account: signing in as somebody else on '
    'the same device does not inherit it',
    (tester) async {
      final first = _container();
      addTearDown(first.dispose);
      await tester.pumpWidget(_harness(first, [_personal]));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Personal space options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from list'));
      await tester.pumpAndSettle();
      expect(find.text(personalSpaceName), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
      first.dispose();

      const otherTokens = api.TokenPair(
        userId: 'other',
        accessToken: 'access-2',
        refreshToken: 'refresh-2',
        accessExpiresAt: 0,
      );
      final second = ProviderContainer(
        overrides: [
          keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
          sessionProvider.overrideWithValue(
            api.SessionStore(tokens: otherTokens),
          ),
          databaseProvider.overrideWith((ref) async {
            final db = SlimmDatabase(NativeDatabase.memory());
            ref.onDispose(db.close);
            return db;
          }),
        ],
      );
      addTearDown(second.dispose);
      await tester.pumpWidget(_harness(second, [_personal]));
      await tester.pumpAndSettle();

      expect(
        find.text(personalSpaceName),
        findsOneWidget,
        reason:
            'a second account\'s own personal space must open visible, '
            'never pre-hidden by the first account\'s choice',
      );

      await tester.pumpWidget(const SizedBox());
    },
  );
}
