// SPDX-License-Identifier: Apache-2.0
/// A terminated app must leave a voice call; a backgrounded one must not.
///
/// Nothing can run once the process is actually killed, so this controller
/// cannot detect its own termination directly. What it can do is keep
/// refreshing proof of life with the server for as long as it is genuinely
/// connected, on an interval independent of the app's foreground state, so a
/// heartbeat that stops arriving is what the server (`voice/heartbeat.rs`)
/// treats as gone rather than waiting on the SFU's own reconnect grace.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_rtc/rtc.dart';

import 'voice_controller_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final harness = VoiceHarness();

  tearDown(harness.dispose);

  Iterable<Uri> heartbeatsIn(List<Uri> requests) =>
      requests.where((u) => u.path.endsWith('/voice/heartbeat'));

  test(
    'joining a call starts an immediate, then periodic, heartbeat',
    () async {
      final requests = <Uri>[];
      final session = FakeSession();
      final controller = harness.controllerWith(
        session,
        voiceApi(onRequest: requests.add),
        voiceHeartbeatInterval: const Duration(milliseconds: 15),
      );

      await controller.join('channel-1');
      // Real room events drive this transition; the fake stands in for one.
      session.emitState(VoiceSessionState.connected);
      // The first beat is fire-and-forget from that transition; let it land.
      await Future<void>.delayed(Duration.zero);
      expect(
        heartbeatsIn(requests),
        isNotEmpty,
        reason: 'the first beat must not wait out a whole interval',
      );

      final afterJoin = heartbeatsIn(requests).length;
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(heartbeatsIn(requests).length, greaterThan(afterJoin));
    },
  );

  test('leaving the call stops the heartbeat', () async {
    final requests = <Uri>[];
    final session = FakeSession();
    final controller = harness.controllerWith(
      session,
      voiceApi(onRequest: requests.add),
      voiceHeartbeatInterval: const Duration(milliseconds: 15),
    );

    await controller.join('channel-1');
    session.emitState(VoiceSessionState.connected);
    await Future<void>.delayed(Duration.zero);
    await controller.leave();
    final afterLeave = heartbeatsIn(requests).length;

    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(
      heartbeatsIn(requests).length,
      afterLeave,
      reason: 'a clean leave must not keep proving a call that ended',
    );
  });

  test('a call the SFU drops stops the heartbeat', () async {
    final requests = <Uri>[];
    final session = FakeSession();
    final controller = harness.controllerWith(
      session,
      voiceApi(onRequest: requests.add),
      voiceHeartbeatInterval: const Duration(milliseconds: 15),
    );

    await controller.join('channel-1');
    session.emitState(VoiceSessionState.connected);
    await Future<void>.delayed(Duration.zero);
    session.dropWith(VoiceDisconnect.removed);
    await Future<void>.delayed(Duration.zero);
    final afterDrop = heartbeatsIn(requests).length;

    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(heartbeatsIn(requests).length, afterDrop);
  });

  test('backgrounding the app does not pause the call heartbeat', () async {
    addTearDown(
      () => TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );

    final requests = <Uri>[];
    final session = FakeSession();
    final controller = harness.controllerWith(
      session,
      voiceApi(onRequest: requests.add),
      voiceHeartbeatInterval: const Duration(milliseconds: 15),
    );

    await controller.join('channel-1');
    session.emitState(VoiceSessionState.connected);
    await Future<void>.delayed(const Duration(milliseconds: 70));

    expect(
      heartbeatsIn(requests).length,
      greaterThanOrEqualTo(3),
      reason: 'a real background call must keep proving it is alive',
    );
  });
}
