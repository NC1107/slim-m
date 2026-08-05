// SPDX-License-Identifier: Apache-2.0
/// [CanvasPresenceLayer]: which bubbles render, whether a live camera view
/// or an avatar fallback fills one, and that panning far away drops a bubble
/// through the viewport hysteresis rather than leaving it stuck forever.
///
/// Deliberately no `ProviderScope` and no [VoiceController]: this widget
/// takes participants and a `cameraViewFor` builder as plain constructor
/// arguments, the same "nothing here reaches Riverpod" rule
/// `canvas_pane_body.dart`'s own doc comment states for its sibling.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/canvas/canvas_presence_layer.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

const _onCamera = VoiceParticipant(
  identity: 'user-priya',
  name: 'Priya',
  isSpeaking: false,
  isMuted: false,
  isLocal: false,
  isScreenSharing: false,
  isCameraOn: true,
);

const _cameraOff = VoiceParticipant(
  identity: 'user-noor',
  name: 'Noor',
  isSpeaking: true,
  isMuted: true,
  isLocal: false,
  isScreenSharing: false,
);

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: buildTheme(Brightness.dark, AppTokens.dark),
    home: Scaffold(body: SizedBox(width: 1000, height: 800, child: child)),
  ),
);

void main() {
  testWidgets('an empty roster renders nothing', (tester) async {
    final document = CanvasDocument();
    addTearDown(document.dispose);

    await tester.pumpWidget(
      _wrap(
        CanvasPresenceLayer(
          document: document,
          participants: const [],
          cameraViewFor: (_) => const SizedBox(),
        ),
      ),
    );
    await tester.pump();
    document.setViewport(const Size(1000, 800));
    await tester.pump();

    expect(find.byType(CanvasPresenceBubble), findsNothing);
  });

  testWidgets(
    'a participant inside the viewport renders exactly one bubble',
    (tester) async {
      final document = CanvasDocument();
      addTearDown(document.dispose);
      document.setViewport(const Size(1000, 800));

      await tester.pumpWidget(
        _wrap(
          CanvasPresenceLayer(
            document: document,
            participants: const [_cameraOff],
            cameraViewFor: (_) => const SizedBox(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CanvasPresenceBubble), findsOneWidget);
    },
  );

  testWidgets('a camera-on participant renders the built camera view', (
    tester,
  ) async {
    final document = CanvasDocument();
    addTearDown(document.dispose);
    document.setViewport(const Size(1000, 800));
    var builtFor = <String>[];

    await tester.pumpWidget(
      _wrap(
        CanvasPresenceLayer(
          document: document,
          participants: const [_onCamera],
          cameraViewFor: (identity) {
            builtFor.add(identity);
            return const ColoredBox(
              key: Key('live-camera'),
              color: Color(0xFF00FF00),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(builtFor, ['user-priya']);
    expect(find.byKey(const Key('live-camera')), findsOneWidget);
  });

  testWidgets(
    'a camera-off participant never calls cameraViewFor, and shows an avatar '
    'instead',
    (tester) async {
      final document = CanvasDocument();
      addTearDown(document.dispose);
      document.setViewport(const Size(1000, 800));
      var calls = 0;

      await tester.pumpWidget(
        _wrap(
          CanvasPresenceLayer(
            document: document,
            participants: const [_cameraOff],
            cameraViewFor: (_) {
              calls++;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();

      expect(calls, 0);
    },
  );

  testWidgets(
    'panning the camera far past the exit band drops a previously-visible '
    'bubble',
    (tester) async {
      final document = CanvasDocument();
      addTearDown(document.dispose);
      document.setViewport(const Size(1000, 800));

      await tester.pumpWidget(
        _wrap(
          CanvasPresenceLayer(
            document: document,
            participants: const [_cameraOff],
            cameraViewFor: (_) => const SizedBox(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CanvasPresenceBubble), findsOneWidget);

      document.setCamera(document.camera.copyWith(x: 100000, y: 100000));
      await tester.pump();

      expect(find.byType(CanvasPresenceBubble), findsNothing);
    },
  );

  testWidgets(
    'the whole layer is wrapped in an ignoring IgnorePointer, so it cannot '
    'steal a pointer the canvas surface underneath still needs',
    (tester) async {
      final document = CanvasDocument();
      addTearDown(document.dispose);
      document.setViewport(const Size(1000, 800));

      await tester.pumpWidget(
        _wrap(
          CanvasPresenceLayer(
            document: document,
            participants: const [_cameraOff],
            cameraViewFor: (_) => const SizedBox(),
          ),
        ),
      );
      await tester.pump();

      final ignorePointer = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(CanvasPresenceBubble),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ignorePointer.ignoring, isTrue);
    },
  );
}
