// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// What the device tells the server about what it is playing (decision 0044):
/// nothing unless switched on, nothing while appearing offline, and never
/// more text than the server's cap.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/activity_feeds.dart';
import 'package:slimm_app/src/providers/activity_publisher.dart';
import 'package:slimm_app/src/providers/activity_sharing_settings.dart';
import 'package:slimm_app/src/providers/live_events.dart';
import 'package:slimm_app/src/providers/presence_controller.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

class _FakeSource implements NowPlayingSource {
  StreamController<NowPlaying?>? _controller;
  int listens = 0;

  @override
  Stream<NowPlaying?> watch() {
    listens++;
    final controller = StreamController<NowPlaying?>(sync: true);
    _controller = controller;
    return controller.stream;
  }

  bool get open => _controller?.hasListener ?? false;

  void play(NowPlaying? track) => _controller?.add(track);
}

class _Harness {
  _Harness({this.source}) {
    container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
        liveEventsProvider.overrideWithValue(events.stream),
        nowPlayingSourceProvider.overrideWithValue(source),
        apiProvider.overrideWith((ref) {
          final client = api.SlimmApi(
            baseUrl: Uri.parse('http://localhost:8080'),
            session: ref.watch(sessionProvider),
            httpClient: MockClient((request) async {
              calls.add(
                '${request.method} ${request.url.path}'
                '${request.body.isEmpty ? '' : ' ${request.body}'}',
              );
              return http.Response('', 204);
            }),
          );
          ref.onDispose(client.close);
          return client;
        }),
      ],
    );
  }

  final _FakeSource? source;
  final events = StreamController<api.ServerEvent>.broadcast(sync: true);
  final calls = <String>[];
  late final ProviderContainer container;

  Future<void> start({bool enabled = false}) async {
    SharedPreferences.setMockInitialValues({
      if (enabled) shareListeningKey: true,
    });
    container.read(activityPublisherProvider);
    await container.read(preferencesProvider.future);
    await settle();
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> dispose() async {
    container.dispose();
    await events.close();
  }
}

Map<String, dynamic> _body(String call) =>
    jsonDecode(call.substring(call.indexOf('{'))) as Map<String, dynamic>;

void main() {
  test('sharing is off by default and reads no player', () async {
    final source = _FakeSource();
    final h = _Harness(source: source);
    addTearDown(h.dispose);
    await h.start();

    expect(h.container.read(shareListeningProvider), isFalse);
    source.play(const NowPlaying(title: 'Song'));
    await h.settle();
    expect(source.listens, 0);
    expect(h.calls, isEmpty);
  });

  test(
    'turning it on sends the playing track, and pausing clears it',
    () async {
      final source = _FakeSource();
      final h = _Harness(source: source);
      addTearDown(h.dispose);
      await h.start();

      await h.container.read(shareListeningProvider.notifier).setEnabled(true);
      await h.settle();
      source.play(const NowPlaying(title: 'Song', artist: 'Artist'));
      await h.settle();
      expect(h.calls, hasLength(1));
      expect(h.calls.single, startsWith('PUT /presence/activity'));
      expect(_body(h.calls.single), {
        'type': 'listening',
        'title': 'Song',
        'subtitle': 'Artist',
      });

      source.play(null);
      await h.settle();
      expect(h.calls.last, 'DELETE /presence/activity');
    },
  );

  test('turning it off clears what was sent and stops the source', () async {
    final source = _FakeSource();
    final h = _Harness(source: source);
    addTearDown(h.dispose);
    await h.start(enabled: true);
    source.play(const NowPlaying(title: 'Song'));
    await h.settle();
    expect(h.calls, hasLength(1));

    await h.container.read(shareListeningProvider.notifier).setEnabled(false);
    await h.settle();
    expect(h.calls.last, 'DELETE /presence/activity');
    expect(source.open, isFalse);
    source.play(const NowPlaying(title: 'Ignored'));
    await h.settle();
    expect(h.calls, hasLength(2));
  });

  test('nothing is sent while appearing offline', () async {
    final source = _FakeSource();
    final h = _Harness(source: source);
    addTearDown(h.dispose);
    await h.start(enabled: true);
    h.container.read(presenceVisibilityDisplayProvider.notifier).state =
        api.PresenceVisibility.hidden;

    await h.settle();
    source.play(const NowPlaying(title: 'Secret'));
    await h.settle();
    expect(h.calls, isEmpty);
    expect(source.open, isFalse);
  });

  test('hiding after sharing clears it, and unhiding shares again', () async {
    final source = _FakeSource();
    final h = _Harness(source: source);
    addTearDown(h.dispose);
    await h.start(enabled: true);
    source.play(const NowPlaying(title: 'Song'));
    await h.settle();

    final visibility = h.container.read(
      presenceVisibilityDisplayProvider.notifier,
    );
    visibility.state = api.PresenceVisibility.hidden;
    await h.settle();
    expect(h.calls.last, 'DELETE /presence/activity');

    expect(source.open, isFalse);

    visibility.state = api.PresenceVisibility.online;
    await h.settle();
    source.play(const NowPlaying(title: 'Song'));
    await h.settle();
    expect(h.calls.last, startsWith('PUT /presence/activity'));
  });

  test('a long title and artist are cut to the server cap', () async {
    final source = _FakeSource();
    final h = _Harness(source: source);
    addTearDown(h.dispose);
    await h.start(enabled: true);

    source.play(NowPlaying(title: 'a' * 500, artist: '\u{1F3B5}' * 300));
    await h.settle();
    final body = _body(h.calls.single);
    expect((body['title'] as String).runes.length, 128);
    expect((body['subtitle'] as String).runes.length, 128);
  });

  test('a reconnect that lost the activity sends it again', () async {
    final source = _FakeSource();
    final h = _Harness(source: source);
    addTearDown(h.dispose);
    await h.start(enabled: true);
    source.play(const NowPlaying(title: 'Song'));
    await h.settle();
    expect(h.calls, hasLength(1));

    h.events.add(
      const api.PresenceChanged(
        userId: 'self',
        status: api.PresenceState.online,
      ),
    );
    await h.settle();
    expect(h.calls, hasLength(2));
    expect(h.calls.last, startsWith('PUT /presence/activity'));
  });

  test('a platform with no source never sends anything', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.start(enabled: true);
    await h.settle();
    expect(h.calls, isEmpty);
  });
}
