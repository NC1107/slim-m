// SPDX-License-Identifier: Apache-2.0
/// The interaction #456's per-object right-click menu and the self camera
/// bubble share one Stack: a right-click landing on the bubble's own tile
/// must never reach a canvas object underneath it. See
/// `canvas_self_presence_overlay.dart`'s own doc for why "absorbed, does
/// nothing" is the deliberate answer, not a side effect of stacking order -
/// this drives both widgets together, stacked exactly as
/// `canvas_pane_body.dart` stacks them, rather than trusting that reading
/// the production code correctly predicts the composed behaviour.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/canvas_self_presence.dart';
import 'package:slimm_app/src/screens/canvas/canvas_object_context_menu.dart';
import 'package:slimm_app/src/screens/canvas/canvas_presence_layer.dart';
import 'package:slimm_app/src/screens/canvas/canvas_self_presence_overlay.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

const _local = VoiceParticipant(
  identity: 'me',
  name: 'Me',
  isSpeaking: false,
  isMuted: false,
  isLocal: true,
  isScreenSharing: false,
);

/// Mirrors `canvas_pane_body.dart`'s own Stack order: the object menu's
/// full-screen catcher first, the self bubble last so it paints - and hit
/// tests - on top of it.
Widget _wrap({
  required CanvasDocument document,
  required CanvasObjectMenuRequests requests,
}) => ProviderScope(
  child: MaterialApp(
    theme: buildTheme(Brightness.dark, AppTokens.dark),
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 400,
        child: Stack(
          children: [
            CanvasObjectContextMenu(
              document: document,
              canManage: false,
              selfId: 'me',
              requests: requests,
              onToolChanged: (_) {},
              onBringToFront: (_) {},
              onSendToBack: (_) {},
              onDeleteSelected: (_) {},
            ),
            CanvasSelfPresenceOverlay(
              participants: const [_local],
              cameraViewFor: (_) => const SizedBox(),
              hidden: false,
              corner: CanvasSelfBubbleCorner.topLeft,
              onCornerChanged: (_) {},
            ),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'a right-click on the self bubble opens no object menu, even for an '
    'object placed directly underneath it',
    (tester) async {
      final document = CanvasDocument()
        ..applyPlaced(
          CanvasStrokeInput(
            id: 'a',
            seq: 1,
            zIndex: 1,
            x: 50,
            y: 50,
            w: 40,
            h: 40,
            points: const [],
            width: 0,
            colorKey: 'shape',
            kind: CanvasObjectKind.shape,
            authorId: 'me',
          ),
        );
      addTearDown(document.dispose);
      final requests = CanvasObjectMenuRequests();
      await tester.pumpWidget(
        _wrap(document: document, requests: requests),
      );

      // The top-left corner's own resting centre (margin 16, a camera-off
      // tile is 104x104): (68, 68), squarely inside the object's own
      // 50..90 world rect - proof this is a real overlap, not a near miss.
      await tester.tapAt(const Offset(68, 68), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Send to back'), findsNothing);
      expect(find.text('Bring to front'), findsNothing);
      expect(document.selectedObjectId.value, isNull);
    },
  );

  testWidgets(
    'a right-click just outside the bubble still reaches the object beneath '
    'it - the absorption is scoped to the tile, not the whole overlay',
    (tester) async {
      final document = CanvasDocument()
        ..applyPlaced(
          CanvasStrokeInput(
            id: 'a',
            seq: 1,
            zIndex: 1,
            x: 150,
            y: 150,
            w: 40,
            h: 40,
            points: const [],
            width: 0,
            colorKey: 'shape',
            kind: CanvasObjectKind.shape,
            authorId: 'me',
          ),
        );
      addTearDown(document.dispose);
      final requests = CanvasObjectMenuRequests();
      await tester.pumpWidget(
        _wrap(document: document, requests: requests),
      );

      // Well past the top-left tile's own 16..120 box on both axes.
      await tester.tapAt(const Offset(170, 170), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Send to back'), findsOneWidget);
      expect(document.selectedObjectId.value, 'a');
    },
  );
}
