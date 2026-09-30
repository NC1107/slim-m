// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Linux now-playing over MPRIS: any local player that exposes
/// `org.mpris.MediaPlayer2.*` on the session bus, with no account linking.
///
/// Polled rather than signal-driven: a few seconds of lag on a track change
/// is fine for presence, and one loop is far simpler than tracking players
/// coming and going. Every failure reads as "nothing playing".
library;

import 'package:dbus/dbus.dart';

import 'now_playing.dart';
import 'polled_stream.dart';

const _mprisPrefix = 'org.mpris.MediaPlayer2.';
const _playerInterface = 'org.mpris.MediaPlayer2.Player';
const _defaultPollInterval = Duration(seconds: 5);

/// A player's own report, before deciding which one is "the" track.
class MprisPlayerState {
  const MprisPlayerState({required this.status, required this.metadata});

  final String status;
  final Map<String, DBusValue> metadata;
}

/// The first player that is playing and names a track, or null.
NowPlaying? pickNowPlaying(Iterable<MprisPlayerState> players) {
  for (final player in players) {
    if (player.status != 'Playing') continue;
    final title = player.metadata['xesam:title']?.asString().trim() ?? '';
    if (title.isEmpty) continue;
    final artists = player.metadata['xesam:artist']?.asStringArray().toList();
    final artist = artists?.where((a) => a.trim().isNotEmpty).join(', ');
    return NowPlaying(
      title: title,
      artist: artist == null || artist.isEmpty ? null : artist,
    );
  }
  return null;
}

class MprisNowPlayingSource implements NowPlayingSource {
  MprisNowPlayingSource({Duration pollInterval = _defaultPollInterval})
      : _pollInterval = pollInterval;

  final Duration _pollInterval;

  @override
  Stream<NowPlaying?> watch() {
    DBusClient? bus;
    return polledStream<NowPlaying>(
      interval: _pollInterval,
      read: () async =>
          pickNowPlaying(await _readPlayers(bus ??= DBusClient.session())),
      onCancel: () async {
        await bus?.close();
        bus = null;
      },
    );
  }

  Future<List<MprisPlayerState>> _readPlayers(DBusClient bus) async {
    final names = (await bus.listNames()).where(
      (n) => n.startsWith(_mprisPrefix),
    );
    final players = <MprisPlayerState>[];
    for (final name in names) {
      final object = DBusRemoteObject(
        bus,
        name: name,
        path: DBusObjectPath('/org/mpris/MediaPlayer2'),
      );
      try {
        final status = await object.getProperty(
          _playerInterface,
          'PlaybackStatus',
        );
        final metadata = await object.getProperty(_playerInterface, 'Metadata');
        players.add(
          MprisPlayerState(
            status: status.asString(),
            metadata: metadata.asStringVariantDict(),
          ),
        );
      } on Object {
        continue;
      }
    }
    return players;
  }
}
