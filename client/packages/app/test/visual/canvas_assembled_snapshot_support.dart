// SPDX-License-Identifier: Apache-2.0
/// The pump-and-capture helper `canvas_assembled_snapshot_test.dart` runs
/// every scene through, split out the same way `ui_snapshot_support.dart`
/// is split from `ui_snapshot_test.dart`: the widths, the themes and the
/// rendering are not what a reader of the test file's scenarios cares about.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/avatar_bytes.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/user_profiles.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/screens/canvas/canvas_activity_log.dart';
import 'package:slimm_app/src/screens/canvas/canvas_call_dock.dart';
import 'package:slimm_app/src/screens/canvas/canvas_pane_body.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import '../voice_controller_harness.dart';

const canvasAssembledOutDir = 'build/canvas-assembled-snapshots';
bool get _writing => Platform.environment['SLIMM_CANVAS_ASSEMBLED'] == '1';

const canvasAssembledThemes =
    <String, ({Brightness brightness, AppTokens tokens})>{
      'light': (brightness: Brightness.light, tokens: AppTokens.light),
      'dark': (brightness: Brightness.dark, tokens: AppTokens.dark),
      'true-black': (brightness: Brightness.dark, tokens: AppTokens.trueBlack),
    };

/// Widths worth a look: a phone, the exact pixel the dock's own one/two-row
/// branch turns on (`kCompactWidth`, both sides), and a wide desktop pane.
const canvasAssembledWidths = <String, double>{
  'phone-390': 390,
  'compact-599': 599,
  'compact-600': 600,
  'desktop-1400': 1400,
};

const _boundaryKey = Key('canvas_assembled_boundary');

Future<void> _writePng(WidgetTester tester, String name) async {
  if (!_writing) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    Directory(canvasAssembledOutDir).createSync(recursive: true);
    File(
      '$canvasAssembledOutDir/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Builds and pumps a [CanvasPaneBody] filling a real [width]x[height]
/// viewport, with a real [VoiceController] wired for the dock's call
/// section whenever [participants] is non-empty. Everything interactive is
/// a no-op: this is a look, not a drive.
Future<void> renderCanvasAssembledPane(
  WidgetTester tester, {
  required String name,
  required double width,
  required String theme,
  required CanvasDocument document,
  List<VoiceParticipant> participants = const [],
  CanvasCursors? cursors,
  bool truncated = false,
  String? selectedObjectId,
  double height = 844,
  CanvasPresenceTileOverrides? tileOverrides,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final session = participants.isEmpty ? null : FakeSession();
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      userProfileProvider.overrideWith((ref, id) async => null),
      avatarBytesProvider.overrideWith((ref, key) async => null),
      if (session != null)
        voiceControllerProvider.overrideWith(
          (ref) => FixedVoiceController(
            ref,
            VoiceState(
              channelId: 'c1',
              state: VoiceSessionState.connected,
              participants: participants,
            ),
          ),
        ),
    ],
  );
  addTearDown(container.dispose);
  final controller = session == null
      ? null
      : container.read(voiceControllerProvider.notifier);

  final activityLog = CanvasActivityLog(isBlocked: (_) => false);
  addTearDown(activityLog.dispose);
  if (selectedObjectId != null) {
    document.selectedObjectId.value = selectedObjectId;
  }
  final overrides = tileOverrides ?? CanvasPresenceTileOverrides();
  if (tileOverrides == null) addTearDown(overrides.dispose);

  final themeSpec = canvasAssembledThemes[theme]!;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(themeSpec.brightness, themeSpec.tokens),
        home: Scaffold(
          body: RepaintBoundary(
            key: _boundaryKey,
            child: CanvasPaneBody(
              channelId: 'c1',
              onClose: () {},
              tool: CanvasTool.pen,
              onToolChanged: (_) {},
              canUndo: false,
              onUndo: () {},
              canManage: false,
              document: document,
              onClear: () async {},
              onPasteImage: () {},
              onRecenter: () {},
              error: null,
              onDismissError: () {},
              truncated: truncated,
              loading: false,
              onStroke: (_) {},
              onErase: (_) {},
              onEraseEnd: () {},
              onSelectStart: (_) {},
              onSelectDrag: (_) {},
              onSelectEnd: () {},
              onNotePlace: (_) {},
              onShapePlace: (_) {},
              shapeKind: CanvasShapeKind.rectangle,
              onShapeKindChanged: (_) {},
              onBringToFront: (_) {},
              onSendToBack: (_) {},
              onDeleteSelected: (_) {},
              selfId: 'me',
              activityLog: activityLog,
              cursors: cursors,
              cursorColors: AppCanvasColors.cursors,
              callParticipants: participants,
              cameraViewFor: (identity) => ColoredBox(
                color: const Color(0xFF223344),
                child: Center(
                  child: Text(
                    identity,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              screenShareViewFor: (identity) => ColoredBox(
                color: const Color(0xFF1D3A2E),
                child: Center(
                  child: Text(
                    "$identity's screen",
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              tileOverrides: overrides,
              selfBubbleHidden: false,
              onToggleSelfBubbleHidden: () {},
              callDock: controller == null
                  ? null
                  : CallDockData(
                      voice: VoiceState(
                        channelId: 'c1',
                        state: VoiceSessionState.connected,
                        participants: participants,
                      ),
                      controller: controller,
                    ),
            ),
          ),
        ),
      ),
    ),
  );
  // Two pumps settle the presence layer's own visibility hysteresis - see ui_snapshot_test.dart's identical reasoning.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));

  await _writePng(tester, name);
  expect(tester.takeException(), isNull);
}
