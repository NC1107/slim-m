// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The channel-backed source (Windows SMTC): a native reply becomes a track,
/// nothing is asked until someone listens, and every failure is "nothing".
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_platform/src/now_playing.dart';
import 'package:slimm_platform/src/now_playing_channel.dart';
import 'package:slimm_platform/src/now_playing_io.dart' as io;
import 'package:slimm_platform/src/now_playing_mpris.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(nowPlayingChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('a reply with a title is a track, the artist is optional', () {
    expect(
      nowPlayingFromChannelReply({'title': ' Song ', 'artist': 'A'}),
      const NowPlaying(title: 'Song', artist: 'A'),
    );
    expect(
      nowPlayingFromChannelReply({'title': 'Song', 'artist': '  '}),
      const NowPlaying(title: 'Song'),
    );
  });

  test('a reply without a usable title is nothing', () {
    expect(nowPlayingFromChannelReply(null), isNull);
    expect(nowPlayingFromChannelReply({'title': '  '}), isNull);
    expect(nowPlayingFromChannelReply({'artist': 'A'}), isNull);
    expect(nowPlayingFromChannelReply('Song'), isNull);
  });

  test('nothing is asked of the runner until someone listens', () async {
    var asked = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      asked++;
      return {'title': 'Song'};
    });
    final source = ChannelNowPlayingSource();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(asked, 0);

    final first = await source.watch().first;
    expect(first, const NowPlaying(title: 'Song'));
    expect(asked, 1);
  });

  test('a paused player reads as null, and only changes are emitted', () async {
    final replies = <Object?>[
      {'title': 'Song'},
      {'title': 'Song'},
      null,
    ];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'current');
      return replies.removeAt(0);
    });
    final source = ChannelNowPlayingSource(
      pollInterval: const Duration(milliseconds: 10),
    );
    final seen = await source.watch().take(2).toList();
    expect(seen, [const NowPlaying(title: 'Song'), null]);
  });

  test('a runner that throws or is missing reads as nothing', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unavailable');
    });
    final source = ChannelNowPlayingSource();
    expect(await source.watch().first, isNull);

    messenger.setMockMethodCallHandler(channel, null);
    expect(await source.watch().first, isNull);
  });

  test('the Windows branch is taken on request, even from Linux', () {
    expect(
      io.createNowPlayingSource(linux: false, windows: true),
      isA<ChannelNowPlayingSource>(),
    );
    expect(
      io.createNowPlayingSource(linux: true, windows: false),
      isA<MprisNowPlayingSource>(),
    );
    expect(io.createNowPlayingSource(linux: false, windows: false), isNull);
  });
}
