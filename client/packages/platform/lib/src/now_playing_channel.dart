// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Now-playing read by the native runner over a method channel. Windows
/// implements it with the system media transport controls (SMTC), which any
/// app that registers a media session shows up in; no account, no network.
///
/// The reply is `{title, artist}` for the playing session or null. The
/// native side is only asked while someone listens, so a switched-off source
/// never reads a session.
library;

import 'package:flutter/services.dart';

import 'now_playing.dart';
import 'polled_stream.dart';

const nowPlayingChannelName = 'slimm/now_playing';
const _defaultPollInterval = Duration(seconds: 5);

/// The playing track in a native reply, or null when it names none.
NowPlaying? nowPlayingFromChannelReply(Object? reply) {
  if (reply is! Map) return null;
  final title = reply['title'];
  if (title is! String || title.trim().isEmpty) return null;
  final artist = reply['artist'];
  return NowPlaying(
    title: title.trim(),
    artist: artist is String && artist.trim().isNotEmpty ? artist.trim() : null,
  );
}

class ChannelNowPlayingSource implements NowPlayingSource {
  ChannelNowPlayingSource({
    MethodChannel channel = const MethodChannel(nowPlayingChannelName),
    Duration pollInterval = _defaultPollInterval,
  })  : _channel = channel,
        _pollInterval = pollInterval;

  final MethodChannel _channel;
  final Duration _pollInterval;

  @override
  Stream<NowPlaying?> watch() => polledStream<NowPlaying>(
        interval: _pollInterval,
        read: () async => nowPlayingFromChannelReply(
          await _channel.invokeMethod<Object>('current'),
        ),
      );
}
