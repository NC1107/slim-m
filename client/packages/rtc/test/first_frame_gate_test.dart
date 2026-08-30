// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Pins the fix for a screen share (and camera) tile painting whatever was
/// already sitting in its texture's GPU memory - stale attachments, emoji,
/// fragments of other UI - before its first real frame arrived.
///
/// `CameraView` and `ScreenShareView` cannot be driven through a real
/// `lk.VideoTrack` here: LiveKit's participant and publication types are
/// unconstructible outside the package (see the same note in
/// `remote_video_publication_test.dart`), so neither view's track-present
/// branch can be reached in a plain widget test. What is tested instead is
/// the actual mechanism both views delegate to - `FirstFrameTracker` and
/// `FirstFrameReveal` - using a real (not faked) `RTCVideoRenderer` for the
/// tracker test, since building one takes no platform channel until
/// `initialize()` is called.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:slimm_rtc/src/first_frame_gate.dart';

void main() {
  group('FirstFrameTracker', () {
    test('has no frame until told otherwise', () {
      expect(FirstFrameTracker().hasFrame, isFalse);
    });

    test('attach wires the real onFirstFrameRendered callback', () {
      final tracker = FirstFrameTracker();
      final renderer = rtc.RTCVideoRenderer();
      tracker.attach(renderer);

      expect(tracker.hasFrame, isFalse);
      renderer.onFirstFrameRendered!();
      expect(tracker.hasFrame, isTrue);
    });

    test('latches true and notifies exactly once', () {
      final tracker = FirstFrameTracker();
      var notifications = 0;
      tracker.addListener(() => notifications++);

      tracker.markFirstFrame();
      tracker.markFirstFrame();

      expect(tracker.hasFrame, isTrue);
      expect(notifications, 1);
    });
  });

  group('FirstFrameReveal', () {
    testWidgets('covers the child with the placeholder before the first frame',
        (
      tester,
    ) async {
      final tracker = FirstFrameTracker();
      await tester.pumpWidget(
        MaterialApp(
          home: FirstFrameReveal(
            tracker: tracker,
            placeholder: const Text('PLACEHOLDER'),
            child: const Text('TEXTURE'),
          ),
        ),
      );

      expect(find.text('PLACEHOLDER'), findsOneWidget);
    });

    testWidgets(
        'reveals the child and drops the placeholder once the frame lands', (
      tester,
    ) async {
      final tracker = FirstFrameTracker();
      await tester.pumpWidget(
        MaterialApp(
          home: FirstFrameReveal(
            tracker: tracker,
            placeholder: const Text('PLACEHOLDER'),
            child: const Text('TEXTURE'),
          ),
        ),
      );

      tracker.markFirstFrame();
      await tester.pump();

      expect(find.text('PLACEHOLDER'), findsNothing);
      expect(find.text('TEXTURE'), findsOneWidget);
    });

    testWidgets(
        'a tracker that already has its frame never shows the placeholder', (
      tester,
    ) async {
      final tracker = FirstFrameTracker()..markFirstFrame();
      await tester.pumpWidget(
        MaterialApp(
          home: FirstFrameReveal(
            tracker: tracker,
            placeholder: const Text('PLACEHOLDER'),
            child: const Text('TEXTURE'),
          ),
        ),
      );

      expect(find.text('PLACEHOLDER'), findsNothing);
      expect(find.text('TEXTURE'), findsOneWidget);
    });
  });
}
