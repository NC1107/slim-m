// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Tests the real [MethodChannelBroadcastBridge], not a fake of it.
///
/// This matters more than it looks. The iOS broadcast upload extension is not
/// in the app: it needs Apple portal objects that do not exist yet, so no
/// host registers this channel and every call misses its handler. What the
/// bridge does with a missing handler is therefore what the iOS share button
/// currently does, and "false" is the only honest answer. Anything else puts
/// the control back to claiming a share nobody can see, which is the bug the
/// whole [ScreenShareOutcome] enum exists to have fixed.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/src/managers/broadcast_manager.dart'
    as lk_broadcast;
import 'package:slimm_rtc/rtc.dart';

/// The default bridge with the platform question answered yes.
///
/// Off a device `lkPlatformIs(iOS)` is false and [BroadcastBridge.isAvailable]
/// returns before reaching the channel at all, so the branch that only iOS
/// takes would otherwise be untestable anywhere this suite can run.
class _AsIfIOS extends MethodChannelBroadcastBridge {
  const _AsIfIOS();

  @override
  bool get usesBroadcastExtension => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannelBroadcastBridge.channel;
  TestDefaultBinaryMessenger messenger() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger().setMockMethodCallHandler(channel, null));

  group('availability', () {
    test('a build whose host does not answer the channel is not available', () {
      messenger().setMockMethodCallHandler(
        channel,
        (call) async => throw MissingPluginException('no handler'),
      );

      expect(
        const _AsIfIOS().isAvailable(),
        completion(isFalse),
        reason:
            'no host handler means no broadcast extension, which is exactly '
            'the state this app ships in today',
      );
    });

    test('a host that refuses the probe is not available either', () {
      messenger().setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'nope'),
      );

      expect(const _AsIfIOS().isAvailable(), completion(isFalse));
    });

    test('an unusable build is reported false, never null-defaulted true', () {
      // A host that answers with nothing has told us nothing. The share
      // cannot be assumed to work on the strength of a null.
      messenger().setMockMethodCallHandler(channel, (call) async => null);

      expect(const _AsIfIOS().isAvailable(), completion(isFalse));
    });

    test('a host with a working extension says so', () {
      messenger().setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'isAvailable');
        return true;
      });

      expect(const _AsIfIOS().isAvailable(), completion(isTrue));
    });

    test('a platform that does not broadcast at all is unaffected', () {
      // Every desktop and Android build. There is no extension to look for,
      // so the question is not asked and screen share is not gated on it.
      expect(
        const MethodChannelBroadcastBridge().usesBroadcastExtension,
        isFalse,
      );
      expect(
        const MethodChannelBroadcastBridge().isAvailable(),
        completion(isTrue),
      );
    });
  });

  group('requestStop', () {
    test('a missing host is not an error to throw at a caller', () {
      messenger().setMockMethodCallHandler(
        channel,
        (call) async => throw MissingPluginException('no handler'),
      );

      expect(const _AsIfIOS().requestStop(), completes);
    });

    test('reaches the host when there is one', () async {
      final calls = <String>[];
      messenger().setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });

      await const _AsIfIOS().requestStop();
      expect(calls, ['requestStop']);
    });

    test('asks nothing of a platform that does not broadcast', () async {
      final calls = <String>[];
      messenger().setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });

      await const MethodChannelBroadcastBridge().requestStop();
      expect(calls, isEmpty);
    });
  });

  group('autoPublishEnabled', () {
    // LiveKit's own singleton, so every test resets it rather than trusting the next file to.
    tearDown(() => lk_broadcast.BroadcastManager().shouldPublishTrack = true);

    test('sets LiveKit\'s own republish flag', () {
      const _AsIfIOS().autoPublishEnabled = false;
      expect(lk_broadcast.BroadcastManager().shouldPublishTrack, isFalse);

      const _AsIfIOS().autoPublishEnabled = true;
      expect(lk_broadcast.BroadcastManager().shouldPublishTrack, isTrue);
    });

    test('a platform that does not broadcast leaves the flag alone', () {
      lk_broadcast.BroadcastManager().shouldPublishTrack = true;
      const MethodChannelBroadcastBridge().autoPublishEnabled = false;

      expect(lk_broadcast.BroadcastManager().shouldPublishTrack, isTrue,
          reason: 'there is nothing to disarm off iOS');
    });
  });

  group('broadcastingChanges', () {
    test('a platform that does not broadcast never emits', () async {
      final events = <bool>[];
      final sub = const MethodChannelBroadcastBridge()
          .broadcastingChanges
          .listen(events.add);
      addTearDown(sub.cancel);

      await pumpEventQueue();
      expect(events, isEmpty);
    });

    test(
        'on iOS a subscription is safe to open and close with nothing '
        'having happened yet', () async {
      final sub = const _AsIfIOS().broadcastingChanges.listen((_) {});
      await pumpEventQueue();
      await sub.cancel();
    });
  });

  // Trips on any change to the livekit `src/` surface the bridge reaches into.
  test('BroadcastManager still exposes the internal surface the bridge uses',
      () {
    addTearDown(
        () => lk_broadcast.BroadcastManager().shouldPublishTrack = true);
    final manager = lk_broadcast.BroadcastManager();

    manager.shouldPublishTrack = false;
    expect(manager.shouldPublishTrack, isFalse);

    void listener() {}
    manager.addListener(listener);
    manager.removeListener(listener);

    expect(manager.isBroadcasting, isA<bool>());
  });
}
