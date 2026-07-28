// SPDX-License-Identifier: Apache-2.0
/// Tests for the voice session, driven through the room-injection seam.
///
/// None of this needs an SFU, which is the point of the seam: the branches
/// worth pinning are the unhappy ones, and a real signalling server can only
/// reliably produce the happy one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:slimm_rtc/rtc.dart';

/// A room that fails to connect, standing in for a bad token, an unreachable
/// SFU, or a network that went away mid-handshake. All three arrive here the
/// same way.
class _FailingRoom extends lk.Room {
  _FailingRoom(this.error);
  final Object error;

  @override
  Future<void> connect(
    String url,
    String token, {
    lk.ConnectOptions? connectOptions,
    lk.RoomOptions? roomOptions,
    lk.FastConnectOptions? fastConnectOptions,
  }) async {
    throw error;
  }
}

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

/// Stands in for the iOS host. [available] is what the app reports about its
/// broadcast extension.
class _FakeBridge implements BroadcastBridge {
  _FakeBridge({this.available = true});

  final bool available;
  int stopRequests = 0;

  @override
  bool get usesBroadcastExtension => true;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestStop() async => stopRequests++;
}

void main() {
  test('a fresh session is idle and holds no error', () {
    final session = VoiceSession(roomFactory: () => lk.Room());
    addTearDown(session.dispose);
    expect(session.state, VoiceSessionState.idle);
    expect(session.participants, isEmpty);
    expect(session.lastError, isNull);
    expect(session.deafened, isFalse);
  });

  test('a refused connection fails the session rather than hanging', () async {
    final session = VoiceSession(
      roomFactory: () => _FailingRoom(StateError('invalid token')),
    );
    addTearDown(session.dispose);

    final seen = <VoiceSessionState>[];
    session.states.listen(seen.add);

    await session.join(url: 'wss://example.invalid', token: 'nope');
    // states is a broadcast stream, so its events land a microtask later than
    // the synchronous state field. Pump before asserting what a listener got.
    await pumpEventQueue();

    expect(session.state, VoiceSessionState.failed);
    expect(session.lastError.toString(), contains('invalid token'));
    expect(
      seen,
      containsAllInOrder([
        VoiceSessionState.connecting,
        VoiceSessionState.failed,
      ]),
      reason: 'the UI needs to see connecting before it sees the failure',
    );
  });

  test('a failed join leaves nothing to clean up behind it', () async {
    final session = VoiceSession(
      roomFactory: () => _FailingRoom(StateError('unreachable')),
    );
    addTearDown(session.dispose);

    await session.join(url: 'wss://example.invalid', token: 'nope');
    expect(session.participants, isEmpty);

    // These must not act on a torn-down room, and must say so rather than
    // throwing into whatever called them. Deafening follows the same rule.
    expect(await session.setMicrophoneEnabled(true), isFalse);
    expect(
      await session.setScreenShareEnabled(true),
      ScreenShareOutcome.failed,
    );
    expect(await session.setDeafened(true), isFalse);
    expect(session.deafened, isFalse);
  });

  group('screen share outcome', () {
    // A bool cannot say what iOS does: the call returns with nothing
    // published, and reporting that as success lit the share button anyway.

    test('publishing nothing reports a pending broadcast, not success',
        () async {
      final session = VoiceSession(
        roomFactory: _EmptyRoom.new,
        broadcast: _FakeBridge(),
      );
      addTearDown(session.dispose);

      await session.join(url: 'wss://a.invalid', token: 't');
      expect(
        await session.setScreenShareEnabled(true),
        ScreenShareOutcome.pendingBroadcast,
        reason: 'no screen track is published, so nobody can see a screen',
      );
    });

    test('a host with no broadcast extension is refused up front', () async {
      final session = VoiceSession(
        roomFactory: _EmptyRoom.new,
        broadcast: _FakeBridge(available: false),
      );
      addTearDown(session.dispose);

      await session.join(url: 'wss://a.invalid', token: 't');
      expect(
        await session.setScreenShareEnabled(true),
        ScreenShareOutcome.unsupported,
        reason: 'waiting on a picker that cannot appear helps nobody',
      );
    });

    test('stopping also ends the platform broadcast', () async {
      // Dropping the track without this leaves the phone still recording,
      // red status bar and all, with nothing being published.
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
  });

  group('deafen', () {
    test('has no effect and reports failure with no room to act on', () async {
      final session = VoiceSession(roomFactory: () => lk.Room());
      addTearDown(session.dispose);

      expect(await session.setDeafened(true), isFalse);
      expect(session.deafened, isFalse);
    });

    test('leaving resets state back to idle without deafen surviving it',
        () async {
      final session = VoiceSession(roomFactory: () => lk.Room());
      addTearDown(session.dispose);

      await session.leave();
      expect(session.state, VoiceSessionState.idle);
      expect(session.deafened, isFalse);
    });
  });

  test('leaving an idle session is safe and stays idle', () async {
    final session = VoiceSession(roomFactory: () => lk.Room());
    addTearDown(session.dispose);
    await session.leave();
    expect(session.state, VoiceSessionState.idle);
  });

  test('a second failed join does not stack a second connection', () async {
    var built = 0;
    final session = VoiceSession(roomFactory: () {
      built++;
      return _FailingRoom(StateError('nope'));
    });
    addTearDown(session.dispose);

    await session.join(url: 'wss://a.invalid', token: 't1');
    await session.join(url: 'wss://a.invalid', token: 't2');

    expect(built, 2, reason: 'each attempt builds its own room');
    expect(session.state, VoiceSessionState.failed);
  });

  test('dispose is idempotent and survives never having joined', () async {
    final session = VoiceSession(roomFactory: () => lk.Room());
    await session.dispose();
    await session.dispose();
    // Calls after disposal must be inert rather than throwing into a widget
    // tree that is already being torn down.
    await session.join(url: 'wss://a.invalid', token: 't');
    expect(session.state, VoiceSessionState.idle);
  });

  group('screen share ceilings', () {
    test('every quality is bounded on all four axes', () {
      // The point of the enum is that no path publishes an unbounded share: 4K
      // at 60fps saturates a home upload and starves the audio it accompanies.
      for (final q in ScreenShareQuality.values) {
        expect(q.width, greaterThan(0));
        expect(q.height, greaterThan(0));
        expect(q.fps, inInclusiveRange(1, 60));
        expect(q.maxBitrate, inInclusiveRange(1, 5000000),
            reason: '${q.name} must stay inside a home upload');
      }
    });

    test('quality trades resolution against frame rate, not just size', () {
      // Smooth is for motion, crisp is for reading code. If crisp were also
      // the highest frame rate it would just be "more", and mean nothing.
      expect(ScreenShareQuality.crisp.width,
          greaterThan(ScreenShareQuality.smooth.width));
      expect(ScreenShareQuality.crisp.fps,
          lessThan(ScreenShareQuality.smooth.fps));
      expect(
          ScreenShareQuality.balanced.fps,
          inInclusiveRange(
              ScreenShareQuality.crisp.fps, ScreenShareQuality.smooth.fps));
    });
  });

  group('VoiceParticipant', () {
    test('compares by value, so an unchanged roster does not rebuild', () {
      const a = VoiceParticipant(
        identity: 'u1',
        name: 'alice',
        isSpeaking: false,
        isMuted: true,
        isLocal: true,
        isScreenSharing: false,
      );
      const b = VoiceParticipant(
        identity: 'u1',
        name: 'alice',
        isSpeaking: false,
        isMuted: true,
        isLocal: true,
        isScreenSharing: false,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('a change in speaking state is a different participant', () {
      const quiet = VoiceParticipant(
        identity: 'u1',
        name: 'alice',
        isSpeaking: false,
        isMuted: false,
        isLocal: false,
        isScreenSharing: false,
      );
      const talking = VoiceParticipant(
        identity: 'u1',
        name: 'alice',
        isSpeaking: true,
        isMuted: false,
        isLocal: false,
        isScreenSharing: false,
      );
      expect(quiet, isNot(equals(talking)));
    });
  });

  group('screen share source', () {
    test('the chosen screen reaches LiveKit as its device id', () {
      final options = VoiceSession.captureOptionsFor(
        ScreenShareQuality.balanced,
        'screen-2',
      );

      // LiveKit carries sourceId as deviceId, and it is the only field
      // getDisplayMedia matches on: dropped, a desktop share cannot start.
      expect(options.deviceId, 'screen-2');
    });

    test('no source named is left unset rather than defaulted', () {
      final options =
          VoiceSession.captureOptionsFor(ScreenShareQuality.balanced, null);

      expect(options.deviceId, isNull);
    });

    test('sources are listed through the injected seam, never a global',
        () async {
      final session = VoiceSession(
        roomFactory: _EmptyRoom.new,
        desktopSources: _FakeSources(const [
          ScreenShareSource(id: '1', name: 'Screen 1'),
        ]),
      );
      addTearDown(session.dispose);

      expect(session.screenShareNeedsSource, isTrue);
      expect((await session.screenShareSources()).single.id, '1');
    });
  });
}

class _FakeSources implements DesktopSources {
  const _FakeSources(this._sources);

  final List<ScreenShareSource> _sources;

  @override
  bool get required => true;

  @override
  Future<List<ScreenShareSource>> list() async => _sources;
}
