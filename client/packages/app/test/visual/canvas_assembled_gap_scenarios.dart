// SPDX-License-Identifier: Apache-2.0
/// Canvas states the assembled-pane harness's own scenario file did not
/// register yet: every error banner, loading, the four non-pen tools, the
/// overflow menu open in its widest conditional shape, and the clear
/// confirmation it guards. Split out purely so
/// `canvas_assembled_snapshot_test.dart` stays a list of scenes.
///
/// Registers `testWidgets` cases directly - called from that file's own
/// `main()`, the same shape `voice_snapshot_scenarios.dart` uses for the
/// surfaces matrix.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'canvas_assembled_scene.dart';
import 'canvas_assembled_snapshot_support.dart';

/// Every message an `AppErrorState` banner can carry above the surface,
/// read verbatim from the source that raises each one rather than
/// paraphrased - see `canvas_pane.dart`, `canvas_commit_queue.dart`,
/// `canvas_pane_helpers.dart` and `canvas_image_paste.dart`.
const _errorMessages = <String, String>{
  'canvas-error-forbidden': 'The canvas is not available in this channel.',
  'canvas-error-generic-load': 'The canvas could not be loaded.',
  'canvas-error-draw-forbidden-timeout-freeze':
      'You cannot draw on this canvas right now.',
  'canvas-error-full-canvas': 'This canvas is full, or that id is taken.',
  'canvas-error-too-large': 'That stroke was refused as too large.',
  'canvas-error-erased-mid-save':
      'That stroke was erased while it was being saved.',
  'canvas-error-image-decode-failed': 'That image could not be read.',
  'canvas-error-image-upload-failed': 'That image could not be uploaded.',
  'canvas-error-image-refused': 'That image was refused.',
  'canvas-error-image-paste-failed': 'That image could not be pasted.',
};

/// The bar's four tools besides the default pen - `Note`, `Shape`,
/// `Eraser` and `Move` (the select tool's own tooltip name) are each
/// `CanvasTool`'s own semantic label, matched against
/// `canvas_tools_row.dart`'s real ones so a rename there fails this rather
/// than silently drifting.
const _tools = <String, CanvasTool>{
  'canvas-tool-note': CanvasTool.note,
  'canvas-tool-shape': CanvasTool.shape,
  'canvas-tool-eraser': CanvasTool.eraser,
  'canvas-tool-select': CanvasTool.select,
};

void registerCanvasErrorBanners() {
  for (final entry in _errorMessages.entries) {
    testWidgets('${entry.key}, dark', (tester) async {
      final document = buildEmptyDocument();
      addTearDown(document.dispose);
      await renderCanvasAssembledPane(
        tester,
        name: '${entry.key}-desktop-1400-dark',
        width: 1400,
        theme: 'dark',
        document: document,
        error: entry.value,
      );
    });
  }
}

void registerCanvasLoading() {
  testWidgets('canvas-loading, dark', (tester) async {
    final document = buildEmptyDocument();
    addTearDown(document.dispose);
    await renderCanvasAssembledPane(
      tester,
      name: 'canvas-loading-desktop-1400-dark',
      width: 1400,
      theme: 'dark',
      document: document,
      loading: true,
    );
  });
}

void registerCanvasToolSelection() {
  for (final entry in _tools.entries) {
    testWidgets('${entry.key}, dark', (tester) async {
      final document = buildBusyDocument();
      addTearDown(document.dispose);
      await renderCanvasAssembledPane(
        tester,
        name: '${entry.key}-desktop-1400-dark',
        width: 1400,
        theme: 'dark',
        document: document,
        tool: entry.value,
      );
    });
  }
}

/// Opened with `canManage: true` and a caller who has a self camera bubble
/// (`busyParticipants` includes `me`), so every conditional row shows at
/// once: paste, recenter, the activity-log toggle, hide-my-camera, and
/// Clear canvas - the widest shape this menu ever renders.
void registerCanvasOverflowMenuOpen() {
  testWidgets('canvas-overflow-menu-open-with-conditional-items, dark', (
    tester,
  ) async {
    final document = buildBusyDocument();
    addTearDown(document.dispose);
    await renderCanvasAssembledPane(
      tester,
      name:
          'canvas-overflow-menu-open-with-conditional-items-desktop-1400-dark',
      width: 1400,
      theme: 'dark',
      document: document,
      participants: busyParticipants,
      canManage: true,
      interact: openCanvasOverflowMenu,
    );
  });
}

/// The activity log panel: the drawing surface unmounted, the panel's own
/// summary and list in its place - reached the same way a real caller
/// would, through the overflow item rather than any test-only shortcut.
void registerCanvasActivityLogOpen() {
  testWidgets('canvas-activity-log-open, dark', (tester) async {
    final document = buildBusyDocument();
    addTearDown(document.dispose);
    await renderCanvasAssembledPane(
      tester,
      name: 'canvas-activity-log-open-desktop-1400-dark',
      width: 1400,
      theme: 'dark',
      document: document,
      interact: (tester) async {
        await openCanvasOverflowMenu(tester);
        await tapCanvasMenuItem(tester, 'Show activity log');
      },
    );
  });
}

/// Clear's own confirmation dialog, object-count-aware copy included -
/// `canManage: true` is what makes the menu item exist to tap at all.
///
/// `showAppSheet`'s desktop branch is a plain `showDialog`, which drives its
/// own fade-in entrance the same t=0-on-mount way `AppFadeIn` does; one more
/// pump than [tapCanvasMenuItem] alone gives is what settles it, the same
/// shape `ui_snapshot_test.dart`'s own `settleJoinTransition` closes.
void registerCanvasClearConfirm() {
  testWidgets('canvas-clear-confirm, dark', (tester) async {
    final document = buildBusyDocument();
    addTearDown(document.dispose);
    await renderCanvasAssembledPane(
      tester,
      name: 'canvas-clear-confirm-desktop-1400-dark',
      width: 1400,
      theme: 'dark',
      document: document,
      canManage: true,
      interact: (tester) async {
        await openCanvasOverflowMenu(tester);
        await tapCanvasMenuItem(tester, 'Clear canvas');
        await tester.pump(const Duration(milliseconds: 200));
      },
    );
  });
}
