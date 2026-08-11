// SPDX-License-Identifier: Apache-2.0
/// [mapVideoSubscriptionRefs]: the decision `VoiceSession`'s own room walk
/// hands off rather than makes itself, and the only part of that walk this
/// package can drive without a signalling server.
///
/// The fixture below gives one participant *both* a camera and a screen
/// share publication, with distinct `subscribe`/`unsubscribe` closures
/// recorded per call, specifically so a mapping that swapped the two kinds
/// - or merged them into one tile - would fail here rather than passing on
/// a fixture with only one publication to get right.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:slimm_rtc/rtc.dart';

/// A publication that records which of its two closures gets called.
class _RecordedPublication {
  _RecordedPublication({
    required this.identity,
    required this.source,
    this.subscribed = true,
  });

  final String identity;
  final lk.TrackSource source;
  final bool subscribed;
  final calls = <String>[];

  RemoteVideoPublicationRef toRef() => (
        identity: identity,
        source: source,
        subscribed: subscribed,
        subscribe: () async => calls.add('subscribe'),
        unsubscribe: () async => calls.add('unsubscribe'),
      );
}

void main() {
  test('a camera publication maps to a camera tile key', () {
    final pub = _RecordedPublication(
      identity: 'alice',
      source: lk.TrackSource.camera,
    );
    final refs = mapVideoSubscriptionRefs([pub.toRef()]).toList();
    expect(refs, hasLength(1));
    expect(refs.single.key, 'camera:alice');
  });

  test(
    'a screen share maps to its own key and is never confused with a '
    'camera, even for the same participant',
    () {
      final camera = _RecordedPublication(
        identity: 'alice',
        source: lk.TrackSource.camera,
      );
      final screen = _RecordedPublication(
        identity: 'alice',
        source: lk.TrackSource.screenShareVideo,
      );
      final refs = mapVideoSubscriptionRefs(
        [camera.toRef(), screen.toRef()],
      ).toList();

      expect(refs.map((r) => r.key).toSet(), {'camera:alice', 'screen:alice'});

      final cameraRef = refs.firstWhere((r) => r.key == 'camera:alice');
      final screenRef = refs.firstWhere((r) => r.key == 'screen:alice');
      cameraRef.unsubscribe();
      screenRef.subscribe();
      expect(
        camera.calls,
        ['unsubscribe'],
        reason: 'the camera key must drive the camera publication, not the '
            'screen share one it shares a participant with',
      );
      expect(
        screen.calls,
        ['subscribe'],
        reason: 'the screen key must drive the screen publication, not the '
            'camera one it shares a participant with',
      );
    },
  );

  test('a participant with both publications yields both', () {
    final refs = mapVideoSubscriptionRefs([
      _RecordedPublication(
        identity: 'bob',
        source: lk.TrackSource.camera,
      ).toRef(),
      _RecordedPublication(
        identity: 'bob',
        source: lk.TrackSource.screenShareVideo,
      ).toRef(),
    ]).toList();
    expect(refs, hasLength(2));
  });

  test(
    'an unknown or future track source is ignored rather than guessed at',
    () {
      for (final source in [
        lk.TrackSource.unknown,
        lk.TrackSource.microphone,
        lk.TrackSource.screenShareAudio,
      ]) {
        final refs = mapVideoSubscriptionRefs([
          _RecordedPublication(identity: 'alice', source: source).toRef(),
        ]).toList();
        expect(
          refs,
          isEmpty,
          reason: '$source has no canvas tile, so nothing should be '
              'produced for it',
        );
      }
    },
  );

  test(
    'subscribed and the two actions carry through from the source '
    'publication unchanged',
    () {
      final pub = _RecordedPublication(
        identity: 'alice',
        source: lk.TrackSource.camera,
        subscribed: false,
      );
      final ref = mapVideoSubscriptionRefs([pub.toRef()]).single;
      expect(ref.subscribed, isFalse);
      ref.subscribe();
      expect(pub.calls, ['subscribe']);
    },
  );
}
