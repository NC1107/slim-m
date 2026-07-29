// SPDX-License-Identifier: Apache-2.0
/// Per-participant volume is offered only where the underlying call actually
/// does something, and that guard is the whole feature on the platforms that
/// cannot do it.
///
/// `Helper.setVolume` works on Android, iOS and macOS. On Linux and Windows
/// it throws an uncaught `PlatformException`: their shared C++ track lookup
/// scans a map that only the Plan B `OnAddStream` callback fills, and LiveKit
/// uses Unified Plan, so it is always empty. On web it resolves having
/// silently discarded a constraint no browser honours.
///
/// Hardcoding the guard true would look perfectly fine on a phone. Fedora is
/// this project's day-to-day target and is one of the two that break, so this
/// pins the guard to the platform rather than to a constant.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:slimm_rtc/rtc.dart';

/// A room that connects without an SFU behind it, so a session can be driven
/// far enough to hold state without any signalling.
class _EmptyRoom extends lk.Room {
  @override
  Future<void> connect(
    String url,
    String token, {
    lk.ConnectOptions? connectOptions,
    lk.RoomOptions? roomOptions,
    lk.FastConnectOptions? fastConnectOptions,
  }) async {}
}

void main() {
  test('support is derived from the platform, never hardcoded', () {
    const works = {
      lk.PlatformType.android,
      lk.PlatformType.iOS,
      lk.PlatformType.macOS,
    };
    expect(supportsParticipantVolume, works.contains(lk.lkPlatform()));
  });

  test('clamps into the range the design offers', () {
    expect(clampParticipantVolume(-1), 0.0);
    expect(clampParticipantVolume(0.5), 0.5);
    expect(clampParticipantVolume(kMaxParticipantVolume), 2.0);
    expect(
      clampParticipantVolume(8),
      kMaxParticipantVolume,
      reason: 'native accepts far more than 2.0, and 8x is painfully loud',
    );
  });

  test('a session reports the default until something sets one', () async {
    final session = VoiceSession(roomFactory: _EmptyRoom.new);
    addTearDown(session.dispose);

    expect(session.volumeFor('maya'), kDefaultParticipantVolume);

    await session.setVolumeFor('maya', 1.3);
    expect(session.volumeFor('maya'), closeTo(1.3, 0.0001));
    expect(
      session.volumeFor('someone-else'),
      kDefaultParticipantVolume,
      reason: 'volume is per participant, not per session',
    );
  });

  test('stores clamped, so no caller can stash a value the UI cannot show',
      () async {
    final session = VoiceSession(roomFactory: _EmptyRoom.new);
    addTearDown(session.dispose);

    await session.setVolumeFor('maya', 99);
    expect(session.volumeFor('maya'), kMaxParticipantVolume);

    await session.setVolumeFor('maya', -4);
    expect(session.volumeFor('maya'), 0.0);
  });

  test('applying gain to a track never throws, whatever the platform does',
      () async {
    // Fired unawaited from a room-event loop, so a throw would be a zone error.
    expect(
      () => applyParticipantVolume(_UnusableTrack(), 1.5),
      returnsNormally,
    );
  });
}

/// A track object that is not backed by anything, standing in for the native
/// lookups that fail to find a remote track on Linux and Windows.
class _UnusableTrack implements lk.Track {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
