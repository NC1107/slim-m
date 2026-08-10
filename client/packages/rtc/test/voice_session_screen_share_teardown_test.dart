// SPDX-License-Identifier: Apache-2.0
/// Screen-share teardown tests, split out of `voice_session_test.dart` for
/// the file budget once this group grew to cover every way a call can end.
///
/// A capture that outlives the call it started for is a privacy failure, not
/// a resource leak, which is why this group covers every path separately
/// rather than trusting one to stand in for the rest.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:slimm_rtc/rtc.dart';

/// A room that connects without an SFU behind it. Its `localParticipant`
/// stays null, which is exactly the shape iOS produces on a share request:
/// the call returns having published nothing.
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

/// Stands in for the iOS host. The hand-off itself has its own dedicated
/// tests in `screen_share_control_test.dart`; this only needs enough of the
/// seam to prove `VoiceSession` reaches it on every teardown path.
class _FakeBridge implements BroadcastBridge {
  @override
  bool get usesBroadcastExtension => true;

  int stopRequests = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> requestStop() async => stopRequests++;

  @override
  set autoPublishEnabled(bool enabled) {}

  @override
  Stream<bool> get broadcastingChanges => const Stream.empty();
}

void main() {
  group('screen share outcome', () {
    test('stopping also ends the platform broadcast', () async {
      // Dropping the track without this leaves the phone still recording.
      final bridge = _FakeBridge();
      final session =
          VoiceSession(roomFactory: _EmptyRoom.new, broadcast: bridge);
      addTearDown(session.dispose);

      await session.join(url: 'wss://a.invalid', token: 't');
      expect(
        await session.setScreenShareEnabled(false),
        ScreenShareOutcome.stopped,
      );
      expect(bridge.stopRequests, 1);
    });

    test('hanging up without stopping the share first still ends it', () async {
      // Leaving a call is not the same button as stopping a share.
      final bridge = _FakeBridge();
      final session =
          VoiceSession(roomFactory: _EmptyRoom.new, broadcast: bridge);
      addTearDown(session.dispose);

      await session.join(url: 'wss://a.invalid', token: 't');
      await session.setScreenShareEnabled(true);
      expect(bridge.stopRequests, 0);

      await session.leave();

      expect(bridge.stopRequests, 1,
          reason: 'a hang-up must not leave the phone still recording');
    });

    test('being removed from the call also ends an active broadcast', () async {
      // The SFU dropping this client never runs through leave() at all.
      final bridge = _FakeBridge();
      late _EmptyRoom room;
      final session = VoiceSession(
        roomFactory: () => room = _EmptyRoom(),
        broadcast: bridge,
      );
      addTearDown(session.dispose);

      await session.join(url: 'wss://a.invalid', token: 't');
      await session.setScreenShareEnabled(true);
      expect(bridge.stopRequests, 0);

      // streamCtrl is the plain stream .listen() subscribes to under emit().
      room.events.streamCtrl.add(
        lk.RoomDisconnectedEvent(
          reason: lk.DisconnectReason.participantRemoved,
        ),
      );
      await pumpEventQueue();

      expect(bridge.stopRequests, 1,
          reason: 'being removed must not leave the phone still recording');
    });

    test('a disconnect this client itself asked for is not double-counted',
        () async {
      // leave() stops the broadcast via _teardown() alone, once.
      final bridge = _FakeBridge();
      final session =
          VoiceSession(roomFactory: _EmptyRoom.new, broadcast: bridge);
      addTearDown(session.dispose);

      await session.join(url: 'wss://a.invalid', token: 't');
      await session.setScreenShareEnabled(true);

      await session.leave();

      expect(bridge.stopRequests, 1);
    });
  });
}
