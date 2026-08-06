// SPDX-License-Identifier: Apache-2.0
/// [CanvasSelfPresenceOverlay] in isolation: which participant it draws (the
/// caller's own, never a remote one), the corner it rests in, that dragging
/// past the pane's own centre line snaps it to a new corner on release, and
/// that a resize recomputes the resting position from the corner rather than
/// keeping a stale pixel offset.
///
/// Deliberately no `ProviderScope`: this widget takes participants, a
/// `cameraViewFor` builder, and the persisted corner/hidden state as plain
/// constructor arguments, the same "nothing here reaches Riverpod" rule
/// `canvas_presence_layer_test.dart` already follows for its sibling layer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/canvas_self_presence.dart';
import 'package:slimm_app/src/screens/canvas/canvas_presence_layer.dart';
import 'package:slimm_app/src/screens/canvas/canvas_self_presence_overlay.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

const _local = VoiceParticipant(
  identity: 'me',
  name: 'Nick',
  isSpeaking: false,
  isMuted: false,
  isLocal: true,
  isScreenSharing: false,
);

const _localOnCamera = VoiceParticipant(
  identity: 'me',
  name: 'Nick',
  isSpeaking: false,
  isMuted: false,
  isLocal: true,
  isScreenSharing: false,
  isCameraOn: true,
);

const _remote = VoiceParticipant(
  identity: 'other',
  name: 'Other',
  isSpeaking: false,
  isMuted: false,
  isLocal: false,
  isScreenSharing: false,
);

const _areaKey = Key('overlay-area');

Widget _wrap(Widget child, {double width = 1000, double height = 800}) =>
    ProviderScope(
      child: MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: Scaffold(
          body: SizedBox(
            key: _areaKey,
            width: width,
            height: height,
            child: Stack(children: [child]),
          ),
        ),
      ),
    );

void main() {
  testWidgets('nobody on the call renders nothing', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CanvasSelfPresenceOverlay(
          participants: const [],
          cameraViewFor: (_) => const SizedBox(),
          hidden: false,
          corner: CanvasSelfBubbleCorner.bottomRight,
          onCornerChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CanvasPresenceBubble), findsNothing);
  });

  testWidgets(
    'a remote-only roster renders nothing - this layer is the caller\'s own '
    'bubble, never someone else\'s',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          CanvasSelfPresenceOverlay(
            participants: const [_remote],
            cameraViewFor: (_) => const SizedBox(),
            hidden: false,
            corner: CanvasSelfBubbleCorner.bottomRight,
            onCornerChanged: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CanvasPresenceBubble), findsNothing);
    },
  );

  testWidgets('hidden renders nothing even with the caller on the call', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CanvasSelfPresenceOverlay(
          participants: const [_local, _remote],
          cameraViewFor: (_) => const SizedBox(),
          hidden: true,
          corner: CanvasSelfBubbleCorner.bottomRight,
          onCornerChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CanvasPresenceBubble), findsNothing);
  });

  testWidgets('unhidden with the caller present renders exactly one bubble', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CanvasSelfPresenceOverlay(
          participants: const [_local, _remote],
          cameraViewFor: (_) => const SizedBox(),
          hidden: false,
          corner: CanvasSelfBubbleCorner.bottomRight,
          onCornerChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CanvasPresenceBubble), findsOneWidget);
  });

  testWidgets('rests at the corner it was given, inset by its margin', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CanvasSelfPresenceOverlay(
          participants: const [_local],
          cameraViewFor: (_) => const SizedBox(),
          hidden: false,
          corner: CanvasSelfBubbleCorner.bottomRight,
          onCornerChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    // Measured, not assumed: the default test surface clamps the requested 1000x800 SizedBox down.
    final area = tester.getRect(find.byKey(_areaKey));
    final bubble = tester.getTopLeft(find.byType(CanvasPresenceBubble));
    // A camera-off tile is 104x104, margin 16.
    expect(
      bubble - area.topLeft,
      Offset(area.width - 104 - 16, area.height - 104 - 16),
    );
  });

  testWidgets(
    'a camera-off self tile is noticeably smaller than a camera-on one - the '
    'least informative tile on the canvas need not spend a full card',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          CanvasSelfPresenceOverlay(
            participants: const [_local],
            cameraViewFor: (_) => const SizedBox(),
            hidden: false,
            corner: CanvasSelfBubbleCorner.bottomRight,
            onCornerChanged: (_) {},
          ),
        ),
      );
      await tester.pump();
      final off = tester.getSize(find.byType(CanvasPresenceBubble));

      await tester.pumpWidget(
        _wrap(
          CanvasSelfPresenceOverlay(
            participants: const [_localOnCamera],
            cameraViewFor: (_) => const ColoredBox(color: Color(0xFF00FF00)),
            hidden: false,
            corner: CanvasSelfBubbleCorner.bottomRight,
            onCornerChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final on = tester.getSize(find.byType(CanvasPresenceBubble));

      expect(off.width * off.height, lessThan(on.width * on.height));
    },
  );

  testWidgets('dragging past the centre line into another quadrant snaps to that '
      'corner on release', (tester) async {
    CanvasSelfBubbleCorner? changed;
    await tester.pumpWidget(
      _wrap(
        CanvasSelfPresenceOverlay(
          participants: const [_local],
          cameraViewFor: (_) => const SizedBox(),
          hidden: false,
          corner: CanvasSelfBubbleCorner.topLeft,
          onCornerChanged: (corner) => changed = corner,
        ),
      ),
    );
    await tester.pump();

    // Resting near (16, 16); dragged well into the bottom-right quadrant of a 1000x800 area.
    await tester.drag(
      find.byType(CanvasPresenceBubble),
      const Offset(900, 700),
    );
    await tester.pump();

    expect(changed, CanvasSelfBubbleCorner.bottomRight);
  });

  testWidgets(
    'a drag that stays inside the same quadrant reports no corner change',
    (tester) async {
      var changes = 0;
      await tester.pumpWidget(
        _wrap(
          CanvasSelfPresenceOverlay(
            participants: const [_local],
            cameraViewFor: (_) => const SizedBox(),
            hidden: false,
            corner: CanvasSelfBubbleCorner.topLeft,
            onCornerChanged: (_) => changes++,
          ),
        ),
      );
      await tester.pump();

      await tester.drag(
        find.byType(CanvasPresenceBubble),
        const Offset(20, 20),
      );
      await tester.pump();

      expect(changes, 0);
    },
  );

  testWidgets(
    'a narrower pane recomputes the resting position from the corner, not a '
    'stale remembered pixel',
    (tester) async {
      // Both widths sit under the default 800x600 test surface, so neither gets clamped.
      await tester.pumpWidget(
        _wrap(
          CanvasSelfPresenceOverlay(
            participants: const [_local],
            cameraViewFor: (_) => const SizedBox(),
            hidden: false,
            corner: CanvasSelfBubbleCorner.topRight,
            onCornerChanged: (_) {},
          ),
          width: 700,
          height: 500,
        ),
      );
      await tester.pump();
      final wideArea = tester.getTopLeft(find.byKey(_areaKey));
      final wideBubble = tester.getTopLeft(find.byType(CanvasPresenceBubble));
      expect((wideBubble - wideArea).dx, 700 - 104 - 16);

      await tester.pumpWidget(
        _wrap(
          CanvasSelfPresenceOverlay(
            participants: const [_local],
            cameraViewFor: (_) => const SizedBox(),
            hidden: false,
            corner: CanvasSelfBubbleCorner.topRight,
            onCornerChanged: (_) {},
          ),
          width: 400,
          height: 500,
        ),
      );
      await tester.pumpAndSettle();
      final narrowArea = tester.getTopLeft(find.byKey(_areaKey));
      final narrowBubble = tester.getTopLeft(find.byType(CanvasPresenceBubble));
      expect((narrowBubble - narrowArea).dx, 400 - 104 - 16);
    },
  );
}
