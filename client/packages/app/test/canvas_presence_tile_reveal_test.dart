// SPDX-License-Identifier: Apache-2.0
/// A presence tile's own lock/depth/hide row and resize grip, hidden until
/// hovered (desktop) or pressed once (touch) - report 3 in the backlog
/// channel: "the buttons... don't ever go away and they are quite large".
///
/// `canvas_presence_depth_test.dart` already covers what these controls do
/// once reached; this file covers whether they can be reached at all, and
/// the one non-negotiable this change must not break: a locked tile still
/// has a way back to its own unlock button.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/canvas/canvas_presence_layer.dart';
import 'package:slimm_app/src/screens/canvas/canvas_presence_tile.dart';
import 'package:slimm_app/src/screens/canvas/canvas_presence_tile_controls.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

const _noor = VoiceParticipant(
  identity: 'user-noor',
  name: 'Noor',
  isSpeaking: false,
  isMuted: false,
  isLocal: false,
  isScreenSharing: false,
);

Widget _wrapLayer(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: buildTheme(Brightness.dark, AppTokens.dark),
    home: Scaffold(body: SizedBox(width: 1000, height: 800, child: child)),
  ),
);

Widget _layer(CanvasDocument document, CanvasPresenceTileOverrides overrides) =>
    CanvasPresenceLayer(
      document: document,
      participants: const [_noor],
      cameraViewFor: (_) => const SizedBox(),
      screenShareViewFor: (_) => const SizedBox(),
      overrides: overrides,
      onCommit: (_, __) {},
    );

const _lockLabel = 'Lock this tile in place';
const _tileKey = ValueKey('camera:user-noor');

void main() {
  testWidgets('the lock control does nothing to a bare tap before the tile '
      'has been hovered or pressed once', (tester) async {
    final document = CanvasDocument()..setViewport(const Size(1000, 800));
    addTearDown(document.dispose);
    final overrides = CanvasPresenceTileOverrides();
    addTearDown(overrides.dispose);

    await tester.pumpWidget(_wrapLayer(_layer(document, overrides)));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel(_lockLabel), warnIfMissed: false);
    await tester.pump();

    expect(
      overrides.stateFor('camera:user-noor').locked,
      isFalse,
      reason:
          'a hidden control must not be tappable, or hidden is only '
          'a visual claim',
    );
  });

  testWidgets(
    'hovering the tile with a mouse reveals the control row, and it stays '
    'reachable for as long as the mouse stays over it',
    (tester) async {
      final document = CanvasDocument()..setViewport(const Size(1000, 800));
      addTearDown(document.dispose);
      final overrides = CanvasPresenceTileOverrides();
      addTearDown(overrides.dispose);

      await tester.pumpWidget(_wrapLayer(_layer(document, overrides)));
      await tester.pump();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(
        location: tester.getCenter(find.byKey(_tileKey)),
      );
      await tester.pump(AppMotion.fast);

      await tester.tap(find.bySemanticsLabel(_lockLabel));
      await tester.pump();

      expect(overrides.stateFor('camera:user-noor').locked, isTrue);
    },
  );

  testWidgets('the mouse leaving the tile hides the control row again', (
    tester,
  ) async {
    final document = CanvasDocument()..setViewport(const Size(1000, 800));
    addTearDown(document.dispose);
    final overrides = CanvasPresenceTileOverrides();
    addTearDown(overrides.dispose);

    await tester.pumpWidget(_wrapLayer(_layer(document, overrides)));
    await tester.pump();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: tester.getCenter(find.byKey(_tileKey)));
    await tester.pump(AppMotion.fast);
    await gesture.moveTo(const Offset(5, 5));
    await tester.pump(AppMotion.fast);

    await tester.tap(find.bySemanticsLabel(_lockLabel), warnIfMissed: false);
    await tester.pump();

    expect(
      overrides.stateFor('camera:user-noor').locked,
      isFalse,
      reason: 'the reveal must not outlive the hover that started it',
    );
  });

  testWidgets(
    'a first touch on the tile reveals the control row for a following tap',
    (tester) async {
      final document = CanvasDocument()..setViewport(const Size(1000, 800));
      addTearDown(document.dispose);
      final overrides = CanvasPresenceTileOverrides();
      addTearDown(overrides.dispose);

      await tester.pumpWidget(_wrapLayer(_layer(document, overrides)));
      await tester.pump();

      await tester.tap(find.byKey(_tileKey));
      await tester.pump(AppMotion.fast);

      await tester.tap(find.bySemanticsLabel(_lockLabel));
      await tester.pump();

      expect(overrides.stateFor('camera:user-noor').locked, isTrue);
    },
  );

  testWidgets('a touch reveal expires on its own after the reveal window, with '
      'nothing else keeping it up', (tester) async {
    final document = CanvasDocument()..setViewport(const Size(1000, 800));
    addTearDown(document.dispose);
    final overrides = CanvasPresenceTileOverrides();
    addTearDown(overrides.dispose);

    await tester.pumpWidget(_wrapLayer(_layer(document, overrides)));
    await tester.pump();

    await tester.tap(find.byKey(_tileKey));
    await tester.pump(
      canvasPresenceTileTouchRevealDuration + const Duration(seconds: 1),
    );

    await tester.tap(find.bySemanticsLabel(_lockLabel), warnIfMissed: false);
    await tester.pump();

    expect(overrides.stateFor('camera:user-noor').locked, isFalse);
  });

  testWidgets(
    'a locked tile still reveals its own unlock button on a touch - the '
    'one control this reveal gate must never hide for good',
    (tester) async {
      final document = CanvasDocument()..setViewport(const Size(1000, 800));
      addTearDown(document.dispose);
      final overrides = CanvasPresenceTileOverrides()
        ..setLocked('camera:user-noor', true);
      addTearDown(overrides.dispose);

      await tester.pumpWidget(_wrapLayer(_layer(document, overrides)));
      await tester.pump();

      // The content area is IgnorePointer'd while locked, so the down event
      // reaches straight through to whatever the tile is stacked over -
      // exactly the surface this test proves the reveal still fires above.
      await tester.tap(find.byKey(_tileKey), warnIfMissed: false);
      await tester.pump(AppMotion.fast);

      await tester.tap(find.bySemanticsLabel('Unlock this tile'));
      await tester.pump();

      expect(overrides.stateFor('camera:user-noor').locked, isFalse);
    },
  );

  testWidgets('the resize grip is also hidden until revealed', (tester) async {
    final document = CanvasDocument()..setViewport(const Size(1000, 800));
    addTearDown(document.dispose);
    final overrides = CanvasPresenceTileOverrides();
    addTearDown(overrides.dispose);

    await tester.pumpWidget(_wrapLayer(_layer(document, overrides)));
    await tester.pump();

    final grip = find.byType(TileResizeGrip);
    expect(grip, findsOneWidget);
    final ignorePointer = find.ancestor(
      of: grip,
      matching: find.byType(IgnorePointer),
    );
    expect(tester.widget<IgnorePointer>(ignorePointer.first).ignoring, isTrue);

    await tester.tap(find.byKey(_tileKey));
    await tester.pump(AppMotion.fast);

    expect(
      tester.widget<IgnorePointer>(ignorePointer.first).ignoring,
      isFalse,
      reason:
          'a reveal must uncover the resize grip exactly as it does '
          'the lock/depth/hide row',
    );
  });
}
