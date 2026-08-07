// SPDX-License-Identifier: Apache-2.0
/// The assembled canvas pane - dock, face-pile, self bubble and surface,
/// together - rendered at real widths in all three themes, with realistic
/// content rather than a handful of test objects.
///
/// This exists because #460's redesign shipped through a rescued,
/// five-conflict landing with nobody having looked at the result on a
/// screen: see CLAUDE.md's own entries on the redesign for why. Every other
/// widget test in this package proves one behaviour in isolation; this one
/// proves the composition - whether the dock, the roster and the self
/// bubble read as one interface once real content is behind them.
///
/// Same shape as `ui_snapshot_test.dart`: the overflow assertion runs
/// everywhere, including CI; the PNGs are only written under
/// `SLIMM_CANVAS_ASSEMBLED=1`, since Skia rasterises differently off this
/// box. Write them with `SLIMM_CANVAS_ASSEMBLED=1 flutter test
/// test/visual/canvas_assembled_snapshot_test.dart` from `client/packages/app`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/canvas_self_presence.dart';

import '../ui_snapshot_support.dart' show loadRealFonts;
import 'canvas_assembled_scene.dart';
import 'canvas_assembled_snapshot_support.dart';

void main() {
  setUpAll(loadRealFonts);

  group(
    'busy: a live call, a busy canvas, a sixth silent cursor-only reader',
    () {
      for (final theme in canvasAssembledThemes.keys) {
        for (final width in canvasAssembledWidths.entries) {
          testWidgets('${width.key} ($theme)', (tester) async {
            final image = await tester.runAsync(
              () => buildGradientImage(
                200,
                150,
                const Color(0xFF3F6FA8),
                const Color(0xFF8FC1E0),
              ),
            );
            final document = buildBusyDocument(hydratedImage: image);
            addTearDown(document.dispose);
            final cursors = buildBusyCursors();
            addTearDown(cursors.dispose);

            await renderCanvasAssembledPane(
              tester,
              name: 'busy-${width.key}-$theme',
              width: width.value,
              theme: theme,
              document: document,
              participants: busyParticipants,
              cursors: cursors,
            );
          });
        }
      }
    },
  );

  group('quiet: the same canvas, nobody on a call and no cursor moving', () {
    for (final theme in canvasAssembledThemes.keys) {
      testWidgets('desktop-1400 ($theme)', (tester) async {
        final document = buildBusyDocument();
        addTearDown(document.dispose);

        await renderCanvasAssembledPane(
          tester,
          name: 'quiet-desktop-1400-$theme',
          width: 1400,
          theme: theme,
          document: document,
        );
      });
    }
  });

  group('empty: no call, no cursor, nothing drawn yet', () {
    for (final theme in canvasAssembledThemes.keys) {
      for (final width in const ['phone-390', 'desktop-1400']) {
        testWidgets('$width ($theme)', (tester) async {
          final document = buildEmptyDocument();
          addTearDown(document.dispose);

          await renderCanvasAssembledPane(
            tester,
            name: 'empty-$width-$theme',
            width: canvasAssembledWidths[width] ?? 1400,
            theme: theme,
            document: document,
          );
        });
      }
    }
  });

  testWidgets('busy phone-390 with an object selected, dark', (tester) async {
    final document = buildBusyDocument();
    addTearDown(document.dispose);
    final cursors = buildBusyCursors();
    addTearDown(cursors.dispose);

    await renderCanvasAssembledPane(
      tester,
      name: 'busy-phone-390-selected-dark',
      width: 390,
      theme: 'dark',
      document: document,
      participants: busyParticipants,
      cursors: cursors,
      selectedObjectId: 'box-cluster',
    );
  });

  testWidgets('busy phone landscape (844x390), dark', (tester) async {
    final document = buildBusyDocument();
    addTearDown(document.dispose);
    final cursors = buildBusyCursors();
    addTearDown(cursors.dispose);

    await renderCanvasAssembledPane(
      tester,
      name: 'busy-phone-landscape-dark',
      width: 844,
      height: 390,
      theme: 'dark',
      document: document,
      participants: busyParticipants,
      cursors: cursors,
    );
  });

  testWidgets(
    'busy desktop-1400 with the self bubble dragged to top-right, dark',
    (tester) async {
      final document = buildBusyDocument();
      addTearDown(document.dispose);
      final cursors = buildBusyCursors();
      addTearDown(cursors.dispose);

      await renderCanvasAssembledPane(
        tester,
        name: 'busy-desktop-1400-self-topright-dark',
        width: 1400,
        theme: 'dark',
        document: document,
        participants: busyParticipants,
        cursors: cursors,
        selfBubbleCorner: CanvasSelfBubbleCorner.topRight,
      );
    },
  );

  testWidgets('busy phone-390 with the truncation banner, dark', (
    tester,
  ) async {
    final document = buildBusyDocument();
    addTearDown(document.dispose);
    final cursors = buildBusyCursors();
    addTearDown(cursors.dispose);

    await renderCanvasAssembledPane(
      tester,
      name: 'busy-phone-390-truncated-dark',
      width: 390,
      theme: 'dark',
      document: document,
      participants: busyParticipants,
      cursors: cursors,
      truncated: true,
    );
  });
}
