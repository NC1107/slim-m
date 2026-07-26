// SPDX-License-Identifier: Apache-2.0
/// Tests for the member pane: the grouping function, and the pane's own
/// live presence data (a real endpoint and a real `presence.changed` event
/// now, not the empty map production used to hand it).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/member_pane.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

UserProfile _profile(String id, String name) => UserProfile(
      id: id,
      username: name.toLowerCase(),
      displayName: name,
      createdAt: 0,
    );

const _tokens = TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// A [SlimmApi] backed by canned answers for `/me` and `/presence`, so a
/// widget test that watches [meProvider] or seeds presence never reaches
/// the network. Signed in: both endpoints require a session, and an
/// unauthenticated call would fail before ever reaching either answer.
SlimmApi _fakeApi(SessionStore session,
    {Map<String, PresenceState> presence = const {}}) {
  return SlimmApi(
    baseUrl: Uri.parse('http://localhost:8080'),
    session: session,
    httpClient: MockClient((request) async {
      if (request.url.path == '/me') {
        return http.Response(
          jsonEncode({
            'id': 'self',
            'username': 'self',
            'display_name': 'Self',
            'created_at': 0,
            'permissions': 0,
          }),
          200,
        );
      }
      if (request.url.path == '/presence') {
        final ids = request.url.queryParameters['ids']?.split(',') ?? [];
        final body = [
          for (final id in ids)
            if (presence[id] != null)
              {'user_id': id, 'status': presence[id]!.name},
        ];
        return http.Response(jsonEncode(body), 200);
      }
      throw StateError('unexpected request in this test: ${request.url}');
    }),
  );
}

List<Override> _overrides({
  required List<UserProfile> members,
  Map<String, PresenceState> presence = const {},
}) =>
    [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
      apiProvider.overrideWith((ref) {
        final api = _fakeApi(ref.watch(sessionProvider), presence: presence);
        ref.onDispose(api.close);
        return api;
      }),
      membersProvider.overrideWith((ref) async => members),
    ];

void main() {
  group('groupMembersByPresence', () {
    test('splits into online and offline, each sorted by name', () {
      final members = [
        _profile('1', 'Zed'),
        _profile('2', 'Anna'),
        _profile('3', 'Mo'),
        _profile('4', 'Kess'),
      ];
      final grouped = groupMembersByPresence(members, {
        '1': AppPresence.online,
        '3': AppPresence.online,
      });

      expect(grouped.online.map((m) => m.displayName), ['Mo', 'Zed']);
      expect(grouped.offline.map((m) => m.displayName), ['Anna', 'Kess']);
    });

    test('away and do-not-disturb group with online, not offline', () {
      final members = [
        _profile('1', 'Away Anna'),
        _profile('2', 'Busy Bo'),
        _profile('3', 'Offline Otto'),
      ];
      final grouped = groupMembersByPresence(members, {
        '1': AppPresence.away,
        '2': AppPresence.dnd,
        '3': AppPresence.offline,
      });

      expect(
          grouped.online.map((m) => m.displayName), ['Away Anna', 'Busy Bo']);
      expect(grouped.offline.single.displayName, 'Offline Otto');
    });

    test('a member absent from the status map counts as offline', () {
      final members = [_profile('1', 'Ren')];
      final grouped = groupMembersByPresence(members, const {});

      expect(grouped.online, isEmpty);
      expect(grouped.offline.single.displayName, 'Ren');
    });

    test('an empty member list produces two empty groups', () {
      final grouped = groupMembersByPresence(const [], const {});
      expect(grouped.online, isEmpty);
      expect(grouped.offline, isEmpty);
    });
  });

  testWidgets(
      'the pane groups real members as offline before presence resolves',
      (tester) async {
    final container = ProviderContainer(
        overrides: _overrides(
      members: [_profile('1', 'Priya'), _profile('2', 'Kess')],
    ));
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: const Scaffold(body: AppMemberPane()),
        ),
      ),
    );
    await tester.pump();

    // Before the presence fetch resolves, both members default to offline
    // rather than being guessed as online.
    expect(find.textContaining('OFFLINE · 2'), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Kess'), findsOneWidget);
    expect(find.textContaining('MEMBERS · 2'), findsOneWidget);
  });

  testWidgets('the pane regroups once real presence resolves', (tester) async {
    final container = ProviderContainer(
        overrides: _overrides(
      members: [_profile('1', 'Priya'), _profile('2', 'Kess')],
      presence: {'1': PresenceState.online, '2': PresenceState.offline},
    ));
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: const Scaffold(body: AppMemberPane()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('ONLINE · 1'), findsOneWidget);
    expect(find.textContaining('OFFLINE · 1'), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Kess'), findsOneWidget);
  });
}
