// SPDX-License-Identifier: Apache-2.0
/// Coverage for `forwardTargetsProvider`: which channels and DMs a forward
/// may actually go to.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/permissions.dart';
import 'package:slimm_app/src/providers/blocks_controller.dart';
import 'package:slimm_app/src/providers/forward_targets.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

Map<String, dynamic> _channelJson({
  required String id,
  required String name,
  int permissions = 0,
}) => {
  'id': id,
  'name': name,
  'kind': 'text',
  'created_at': 0,
  'permissions': permissions,
};

Map<String, dynamic> _userJson(String id, String displayName) => {
  'id': id,
  'username': id,
  'display_name': displayName,
  'created_at': 0,
};

Map<String, dynamic> _dmJson({
  required String channelId,
  required String userId,
  required String displayName,
}) => {
  'channel_id': channelId,
  'user': _userJson(userId, displayName),
  'unread': 0,
  'created_at': 0,
};

ProviderContainer _containerWith({
  required List<Map<String, dynamic>> channels,
  required List<Map<String, dynamic>> dms,
  List<String> blocked = const [],
}) {
  final client = MockClient((request) async {
    if (request.url.path == '/channels') {
      return http.Response(jsonEncode(channels), 200);
    }
    if (request.url.path == '/dms') {
      return http.Response(jsonEncode(dms), 200);
    }
    if (request.url.path == '/blocks') {
      return http.Response(jsonEncode(blocked), 200);
    }
    return http.Response('{}', 404);
  });
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      apiProvider.overrideWith((ref) {
        final slimmApi = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: client,
        );
        ref.onDispose(slimmApi.close);
        return slimmApi;
      }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('offers a channel the caller may send in, and excludes one they '
      'may not', () async {
    final container = _containerWith(
      channels: [
        _channelJson(id: 'c1', name: 'general', permissions: Perm.sendMessages),
        _channelJson(id: 'c2', name: 'announcements', permissions: 0),
      ],
      dms: const [],
    );

    final targets = await container.read(
      forwardTargetsProvider('nowhere').future,
    );

    expect(targets.map((t) => t.channelId), ['c1']);
    expect(targets.single.label, 'general');
  });

  test('excludes the channel the message already sits in', () async {
    final container = _containerWith(
      channels: [
        _channelJson(id: 'c1', name: 'general', permissions: Perm.sendMessages),
      ],
      dms: const [],
    );

    final targets = await container.read(forwardTargetsProvider('c1').future);

    expect(targets, isEmpty);
  });

  test('offers a DM, labelled with the other participant\'s name', () async {
    final container = _containerWith(
      channels: const [],
      dms: [_dmJson(channelId: 'dm1', userId: 'u-priya', displayName: 'Priya')],
    );

    final targets = await container.read(
      forwardTargetsProvider('nowhere').future,
    );

    expect(targets.single.channelId, 'dm1');
    expect(targets.single.label, 'Priya');
  });

  test('a DM with a blocked party is never offered', () async {
    final container = _containerWith(
      channels: const [],
      dms: [_dmJson(channelId: 'dm1', userId: 'u-priya', displayName: 'Priya')],
      blocked: ['u-priya'],
    );
    // The real app has this settled well before a forward sheet can open -
    // `blocksProvider`'s own doc comment: "watched at the shell so it loads
    // with the app". Forced here, the same way the shell forces it in
    // production, so this test does not depend on beating an unrelated
    // fetch in a race.
    await container.read(blocksProvider.notifier).refresh();

    final targets = await container.read(
      forwardTargetsProvider('nowhere').future,
    );

    expect(targets, isEmpty);
  });

  test('the caller\'s own personal space is labelled "You"', () async {
    final container = _containerWith(
      channels: const [],
      dms: [_dmJson(channelId: 'dm-self', userId: 'self', displayName: 'Self')],
    );

    final targets = await container.read(
      forwardTargetsProvider('nowhere').future,
    );

    expect(targets.single.label, 'You');
  });
}
