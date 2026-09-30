// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The Settings switch as link and unlink, and Spotify through the real
/// publisher: off by default, no Spotify request while hidden, and a
/// redirect that is not ours is ignored by the deep-link handler.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/deep_links.dart';
import 'package:slimm_app/src/providers/activity_feeds.dart';
import 'package:slimm_app/src/providers/activity_publisher.dart';
import 'package:slimm_app/src/providers/live_events.dart';
import 'package:slimm_app/src/providers/presence_controller.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/spotify/spotify_client.dart';
import 'package:slimm_app/src/spotify/spotify_config.dart';
import 'package:slimm_app/src/spotify/spotify_link.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

class _Rig {
  _Rig({String clientId = 'client-id', this.launches = true}) {
    container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(keys),
        sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
        liveEventsProvider.overrideWithValue(const Stream.empty()),
        nowPlayingSourceProvider.overrideWithValue(null),
        gameSourceProvider.overrideWithValue(null),
        spotifyClientIdProvider.overrideWithValue(clientId),
        deepLinkUrisProvider.overrideWithValue(links.stream),
        spotifyLauncherProvider.overrideWithValue((uri) async {
          launched.add(uri);
          return launches;
        }),
        spotifyClientProvider.overrideWithValue(
          SpotifyClient(
            client: MockClient((request) async {
              spotify.add('${request.method} ${request.url.host}');
              if (request.url.host == 'accounts.spotify.com') {
                return http.Response(
                  jsonEncode({
                    'access_token': 'a',
                    'refresh_token': 'r',
                    'expires_in': 3600,
                  }),
                  200,
                );
              }
              return http.Response(
                '{"is_playing":true,"currently_playing_type":"track",'
                '"item":{"name":"Song","artists":[]}}',
                200,
              );
            }),
            clientId: clientId,
          ),
        ),
        apiProvider.overrideWith((ref) {
          final client = api.SlimmApi(
            baseUrl: Uri.parse('http://localhost:8080'),
            session: ref.watch(sessionProvider),
            httpClient: MockClient((request) async {
              calls.add('${request.method} ${request.url.path}');
              return http.Response('', 204);
            }),
          );
          ref.onDispose(client.close);
          return client;
        }),
      ],
    );
  }

  final bool launches;
  final keys = InMemoryKeyStore();
  final links = StreamController<Uri>.broadcast(sync: true);
  final launched = <Uri>[];
  final spotify = <String>[];
  final calls = <String>[];
  late final ProviderContainer container;

  Future<void> start({bool enabled = false}) async {
    SharedPreferences.setMockInitialValues({
      if (enabled) shareSpotifyKey: true,
    });
    await container.read(preferencesProvider.future);
    container.read(activityPublisherProvider);
    await settle();
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  Future<void> approve({String? state, String code = 'the-code'}) async {
    await settle();
    final sent = launched.single.queryParameters['state'];
    links.add(
      Uri.parse('slimm://spotify-callback?code=$code&state=${state ?? sent}'),
    );
    await settle();
  }

  Future<void> dispose() async {
    container.dispose();
    await links.close();
  }
}

void main() {
  test('the feature is absent from a build with no client id', () async {
    final rig = _Rig(clientId: '');
    addTearDown(rig.dispose);
    await rig.start();
    expect(rig.container.read(availableActivityFeedsProvider), isEmpty);
    expect(await rig.container.read(spotifyLinkerProvider).link(), isFalse);
    expect(rig.launched, isEmpty);
  });

  test('it is off by default and makes no Spotify request', () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    await rig.start();
    expect(rig.container.read(shareSpotifyProvider), isFalse);
    expect(rig.spotify, isEmpty);
    expect(rig.calls, isEmpty);
  });

  test('turning it on links, and only then turns on', () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    await rig.start();
    final on = rig.container
        .read(shareSpotifyProvider.notifier)
        .setEnabled(true);
    await rig.approve();
    await on;

    final authorize = rig.launched.single;
    expect(authorize.host, 'accounts.spotify.com');
    expect(authorize.queryParameters['client_id'], 'client-id');
    expect(rig.container.read(shareSpotifyProvider), isTrue);
    expect(
      (await rig.container.read(spotifyTokenStoreProvider).load())?.accessToken,
      'a',
    );
  });

  test('a redirect with the wrong state links nothing', () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    await rig.start();
    final on = rig.container
        .read(shareSpotifyProvider.notifier)
        .setEnabled(true);
    await rig.approve(state: 'forged');
    await on;

    expect(rig.container.read(shareSpotifyProvider), isFalse);
    expect(rig.container.read(spotifyLinkErrorProvider), isNotNull);
    expect(await rig.container.read(spotifyTokenStoreProvider).load(), isNull);
  });

  test('a browser that will not open is reported and leaves it off', () async {
    final rig = _Rig(launches: false);
    addTearDown(rig.dispose);
    await rig.start();
    await rig.container.read(shareSpotifyProvider.notifier).setEnabled(true);
    expect(rig.container.read(shareSpotifyProvider), isFalse);
    expect(rig.container.read(spotifyLinkErrorProvider), contains('browser'));
  });

  test('turning it off deletes the token and clears the activity', () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    await rig.start();
    final on = rig.container
        .read(shareSpotifyProvider.notifier)
        .setEnabled(true);
    await rig.approve();
    await on;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(rig.calls, contains('PUT /presence/activity'));

    await rig.container.read(shareSpotifyProvider.notifier).setEnabled(false);
    await rig.settle();
    expect(await rig.container.read(spotifyTokenStoreProvider).load(), isNull);
    expect(rig.calls.last, 'DELETE /presence/activity');
  });

  test('hidden makes no Spotify request and sends nothing', () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    await rig.container
        .read(spotifyTokenStoreProvider)
        .save(
          SpotifyTokens(
            accessToken: 'a',
            refreshToken: 'r',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
    rig.container.read(presenceVisibilityDisplayProvider.notifier).state =
        api.PresenceVisibility.hidden;
    await rig.start(enabled: true);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(rig.spotify, isEmpty);
    expect(rig.calls, isEmpty);
  });

  test('a linked device sends the track while visible', () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    await rig.container
        .read(spotifyTokenStoreProvider)
        .save(
          SpotifyTokens(
            accessToken: 'a',
            refreshToken: 'r',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
    await rig.start(enabled: true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(rig.calls, ['PUT /presence/activity']);
  });

  test(
    'the spotify redirect is ignored by the invite and message handlers',
    () {
      final uri = Uri.parse('slimm://spotify-callback?code=c&state=s');
      expect(inviteFromDeepLink(uri, signedIn: false), isNull);
      expect(
        messageFromDeepLink(uri, signedInTo: Uri.parse('https://x.test')),
        isNull,
      );
    },
  );
}
