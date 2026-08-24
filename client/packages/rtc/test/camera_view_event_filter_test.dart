// SPDX-License-Identifier: Apache-2.0
/// CP4: a camera or screen-share tile must rebuild only on events that can
/// change its own participant's video, not on every room event. LiveKit emits
/// `ActiveSpeakersChanged` several times a second for as long as anyone talks,
/// and the old code ran a full rebuild of every mounted tile on each one.
///
/// This is the regression that matters, and it is what these tests pin: the
/// speaker-change noise no longer rebuilds a tile. The positive branch of the
/// filter (a track this participant published/subscribed/muted, or the
/// participant joining or leaving) cannot be exercised here - LiveKit's
/// participant and publication types are unconstructible outside the package
/// (`createFromInfo` is `@internal` and its result type is hidden from the
/// barrel) - so it is guarded instead by the compiler (the filter names those
/// exact event classes) and by the real camera/screen-share e2e run.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_rtc/src/camera_view.dart';
import 'package:slimm_rtc/src/screen_share_view.dart';
import 'package:slimm_rtc/src/track_event_filter.dart';

void main() {
  test('a busy-room speaker change concerns no particular tile', () {
    // The dominant noise: several a second while anyone is talking.
    expect(
      trackEventAffectsIdentity(
        const lk.ActiveSpeakersChangedEvent(speakers: []),
        'me',
      ),
      isFalse,
    );
  });

  testWidgets('CameraView does not rebuild on room speaker-change noise', (
    tester,
  ) async {
    debugResetCameraViewBuildCounts();
    final room = lk.Room();
    final facing = ValueNotifier(CameraFacing.front);
    addTearDown(facing.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CameraView(room: room, identity: 'me', facing: facing),
      ),
    );
    expect(debugCameraViewBuildCounts['me'], 1);

    for (var i = 0; i < 3; i++) {
      // ignore: invalid_use_of_internal_member
      room.events.emit(const lk.ActiveSpeakersChangedEvent(speakers: []));
      await tester.pump();
    }
    expect(
      debugCameraViewBuildCounts['me'],
      1,
      reason: 'a speaker change cannot alter this tile, so it must not rebuild',
    );

    // The mirror still follows a local camera flip, on its own listener.
    facing.value = CameraFacing.back;
    await tester.pump();
    expect(debugCameraViewBuildCounts['me'], 2);

    // Unmount, then dispose the room (via runAsync, since its cleanup uses real timers FakeAsync will not advance) before the pending-timer check.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(room.dispose);
  });

  testWidgets('ScreenShareView does not rebuild on room speaker-change noise', (
    tester,
  ) async {
    debugResetScreenShareViewBuildCounts();
    final room = lk.Room();

    await tester.pumpWidget(
      MaterialApp(
        home: ScreenShareView(room: room, identity: 'me'),
      ),
    );
    expect(debugScreenShareViewBuildCounts['me'], 1);

    for (var i = 0; i < 3; i++) {
      // ignore: invalid_use_of_internal_member
      room.events.emit(const lk.ActiveSpeakersChangedEvent(speakers: []));
      await tester.pump();
    }
    expect(
      debugScreenShareViewBuildCounts['me'],
      1,
      reason: 'a speaker change cannot alter this tile, so it must not rebuild',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(room.dispose);
  });
}
