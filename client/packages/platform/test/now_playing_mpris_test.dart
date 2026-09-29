// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Choosing the track out of what MPRIS players report.
library;

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_platform/src/now_playing_mpris.dart';

MprisPlayerState _player(
  String status, {
  String? title,
  List<String> artists = const [],
}) =>
    MprisPlayerState(
      status: status,
      metadata: {
        if (title != null) 'xesam:title': DBusString(title),
        'xesam:artist': DBusArray.string(artists),
      },
    );

void main() {
  test('reports the playing track with its artists joined', () {
    final picked = pickNowPlaying([
      _player('Playing', title: 'Song', artists: ['A', 'B']),
    ]);
    expect(picked?.title, 'Song');
    expect(picked?.artist, 'A, B');
  });

  test('a paused or stopped player reports nothing', () {
    expect(pickNowPlaying([_player('Paused', title: 'Song')]), isNull);
    expect(pickNowPlaying([_player('Stopped', title: 'Song')]), isNull);
  });

  test('skips a playing player with no title and takes the next', () {
    final picked = pickNowPlaying([
      _player('Playing'),
      _player('Playing', title: 'Second'),
    ]);
    expect(picked?.title, 'Second');
    expect(picked?.artist, isNull);
  });

  test('no players means nothing playing', () {
    expect(pickNowPlaying(const []), isNull);
  });
}
