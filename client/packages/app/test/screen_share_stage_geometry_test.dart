// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The non-canvas call view's own screen-share stage - the "large share
/// area" a report suggested might not fit its video cleanly against the
/// rounded container, edges disagreeing.
///
/// `ScreenShareStage` places its video through `Positioned.fill` inside the
/// same `ClipRRect` that draws the rounded container, which by Flutter's own
/// layout contract makes the two boxes identical - there is no seam a
/// widget-level bug could open here. This measures the real rendered `Rect`s
/// to prove that rather than assume it, so a future change to this file's
/// `Stack` nesting cannot reopen the gap unnoticed. Any visual mismatch in a
/// screenshot has to come from the video track's own internal letterboxing,
/// not from this widget's layout.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/screen_share_stage.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _harness(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.dark, AppTokens.dark),
  home: Scaffold(body: SizedBox(width: 900, height: 500, child: child)),
);

void main() {
  testWidgets(
    "the video content's box exactly matches the rounded container's own "
    'clip - never letterboxed or offset against it at the widget level',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          ScreenShareStage(
            sharerName: 'Jellyfin',
            child: Container(key: const Key('video'), color: Colors.blue),
          ),
        ),
      );
      await tester.pump();

      final containerRect = tester.getRect(find.byType(ClipRRect));
      final videoRect = tester.getRect(find.byKey(const Key('video')));

      expect(
        videoRect,
        containerRect,
        reason:
            "Positioned.fill guarantees this: the video's box is defined "
            "to be the clip's own box, not merely observed to match it",
      );
    },
  );

  testWidgets('the same holds at a narrow, phone-width stage size', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 220,
            child: ScreenShareStage(
              sharerName: 'Jellyfin',
              child: Container(key: const Key('video'), color: Colors.blue),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final containerRect = tester.getRect(find.byType(ClipRRect));
    final videoRect = tester.getRect(find.byKey(const Key('video')));

    expect(videoRect, containerRect);
  });
}
