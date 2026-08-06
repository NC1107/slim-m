// SPDX-License-Identifier: Apache-2.0
/// The canvas bar in isolation: the pen/eraser toggle, the undo button's
/// enabled state, and the clear control's gating, confirm and reach by
/// touch. `canvas_pane_test.dart` covers the header's own affordance into
/// the pane; this covers what the pane hands the bar.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/canvas/canvas_bar.dart';
import 'package:slimm_app/src/screens/canvas/canvas_shape_icons.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

Widget _wrap(Widget child, {double width = 800}) => MaterialApp(
  theme: buildTheme(Brightness.dark, AppTokens.dark),
  home: Scaffold(
    body: SizedBox(width: width, child: child),
  ),
);

CanvasBar _bar({
  CanvasTool tool = CanvasTool.pen,
  ValueChanged<CanvasTool>? onToolChanged,
  bool canUndo = false,
  VoidCallback? onUndo,
  bool canManage = false,
  ValueListenable<int>? objectCount,
  Future<void> Function()? onClear,
  VoidCallback? onPasteImage,
  ValueListenable<String?>? selection,
  ValueChanged<String>? onBringToFront,
  ValueChanged<String>? onSendToBack,
  ValueChanged<String>? onDeleteSelected,
  bool activityLogOpen = false,
  VoidCallback? onToggleActivityLog,
  CanvasShapeKind shapeKind = CanvasShapeKind.rectangle,
  ValueChanged<CanvasShapeKind>? onShapeKindChanged,
}) => CanvasBar(
  channelId: 'c1',
  onClose: () {},
  tool: tool,
  onToolChanged: onToolChanged ?? (_) {},
  canUndo: canUndo,
  onUndo: onUndo ?? () {},
  canManage: canManage,
  objectCount: objectCount ?? ValueNotifier<int>(3),
  onClear: onClear ?? () async {},
  onPasteImage: onPasteImage ?? () {},
  selection: selection ?? ValueNotifier<String?>(null),
  onBringToFront: onBringToFront ?? (_) {},
  onSendToBack: onSendToBack ?? (_) {},
  onDeleteSelected: onDeleteSelected ?? (_) {},
  activityLogOpen: activityLogOpen,
  onToggleActivityLog: onToggleActivityLog ?? () {},
  shapeKind: shapeKind,
  onShapeKindChanged: onShapeKindChanged ?? (_) {},
);

void main() {
  testWidgets('tapping the eraser calls onToolChanged with eraser', (
    tester,
  ) async {
    CanvasTool? chosen;
    await tester.pumpWidget(
      _wrap(_bar(onToolChanged: (tool) => chosen = tool)),
    );

    await tester.tap(find.bySemanticsLabel('Eraser'));
    await tester.pump();

    expect(chosen, CanvasTool.eraser);
  });

  testWidgets('tapping the pen calls onToolChanged with pen', (tester) async {
    CanvasTool? chosen;
    await tester.pumpWidget(
      _wrap(
        _bar(tool: CanvasTool.eraser, onToolChanged: (tool) => chosen = tool),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Pen'));
    await tester.pump();

    expect(chosen, CanvasTool.pen);
  });

  testWidgets('tapping select calls onToolChanged with select', (tester) async {
    CanvasTool? chosen;
    await tester.pumpWidget(
      _wrap(_bar(onToolChanged: (tool) => chosen = tool)),
    );

    await tester.tap(find.bySemanticsLabel('Move'));
    await tester.pump();

    expect(chosen, CanvasTool.select);
  });

  testWidgets('tapping note or shape calls onToolChanged with that tool', (
    tester,
  ) async {
    CanvasTool? chosen;
    await tester.pumpWidget(
      _wrap(_bar(onToolChanged: (tool) => chosen = tool)),
    );

    await tester.tap(find.bySemanticsLabel('Note'));
    await tester.pump();
    expect(chosen, CanvasTool.note);

    await tester.tap(find.bySemanticsLabel('Shape'));
    await tester.pump();
    expect(chosen, CanvasTool.shape);
  });

  testWidgets(
    'the shape-kind picker only appears in the overflow while the shape '
    'tool is active, and picking one fires onShapeKindChanged',
    (tester) async {
      CanvasShapeKind? chosen;
      await tester.pumpWidget(
        _wrap(_bar(onShapeKindChanged: (kind) => chosen = kind)),
      );
      await tester.tap(find.bySemanticsLabel('More canvas actions'));
      await tester.pumpAndSettle();
      expect(find.text('Ellipse'), findsNothing);

      await tester.pumpWidget(
        _wrap(
          _bar(
            tool: CanvasTool.shape,
            onShapeKindChanged: (kind) => chosen = kind,
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('More canvas actions'));
      await tester.pumpAndSettle();
      expect(find.text('Ellipse'), findsOneWidget);

      await tester.tap(find.text('Ellipse'));
      await tester.pump();
      expect(chosen, CanvasShapeKind.ellipse);
    },
  );

  /// A control whose look never changes with its own state is one a person
  /// has to remember rather than read; this is what stops the Shape button
  /// staying the generic glyph no matter which primitive is armed.
  testWidgets(
    "the Shape button's own icon reflects the currently armed kind",
    (tester) async {
      for (final kind in CanvasShapeKind.values) {
        await tester.pumpWidget(_wrap(_bar(shapeKind: kind)));

        final button = tester.widget<AppIconButton>(
          find.ancestor(
            of: find.bySemanticsLabel('Shape'),
            matching: find.byType(AppIconButton),
          ),
        );
        expect(button.icon, canvasShapeKindIcon(kind), reason: 'kind: $kind');
        expect(
          button.tooltip,
          contains(canvasShapeKindLabel(kind)),
          reason: 'kind: $kind, for a screen reader on the same fact',
        );
      }
    },
  );

  testWidgets('tapping paste image in the overflow calls onPasteImage', (
    tester,
  ) async {
    var pasted = 0;
    await tester.pumpWidget(_wrap(_bar(onPasteImage: () => pasted++)));

    await tester.tap(find.bySemanticsLabel('More canvas actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste image'));
    await tester.pump();

    expect(pasted, 1);
  });

  testWidgets('undo is disabled when canUndo is false', (tester) async {
    var undone = 0;
    await tester.pumpWidget(
      _wrap(_bar(canUndo: false, onUndo: () => undone++)),
    );

    final button = tester.widget<AppIconButton>(
      find.ancestor(
        of: find.bySemanticsLabel('Undo'),
        matching: find.byType(AppIconButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(undone, 0);
  });

  testWidgets('undo fires onUndo when canUndo is true', (tester) async {
    var undone = 0;
    await tester.pumpWidget(_wrap(_bar(canUndo: true, onUndo: () => undone++)));

    await tester.tap(find.bySemanticsLabel('Undo'));
    await tester.pump();

    expect(undone, 1);
  });

  testWidgets('the overflow is always present, but offers no Clear canvas item '
      'without MANAGE_CANVAS', (tester) async {
    await tester.pumpWidget(_wrap(_bar(canManage: false)));
    expect(find.bySemanticsLabel('More canvas actions'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('More canvas actions'));
    await tester.pumpAndSettle();

    expect(find.text('Paste image'), findsOneWidget);
    expect(find.text('Clear canvas'), findsNothing);
  });

  testWidgets('the overflow offers Clear canvas with MANAGE_CANVAS', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_bar(canManage: true)));

    await tester.tap(find.bySemanticsLabel('More canvas actions'));
    await tester.pumpAndSettle();

    expect(find.text('Paste image'), findsOneWidget);
    expect(find.text('Clear canvas'), findsOneWidget);
  });

  testWidgets(
    'Bring to front and Send to back are absent with nothing selected',
    (tester) async {
      await tester.pumpWidget(
        _wrap(_bar(selection: ValueNotifier<String?>(null))),
      );

      await tester.tap(find.bySemanticsLabel('More canvas actions'));
      await tester.pumpAndSettle();

      expect(find.text('Bring to front'), findsNothing);
      expect(find.text('Send to back'), findsNothing);
    },
  );

  testWidgets(
    'Bring to front and Send to back appear and fire with an object selected',
    (tester) async {
      String? front;
      String? back;
      await tester.pumpWidget(
        _wrap(
          _bar(
            selection: ValueNotifier<String?>('obj-1'),
            onBringToFront: (id) => front = id,
            onSendToBack: (id) => back = id,
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('More canvas actions'));
      await tester.pumpAndSettle();
      expect(find.text('Bring to front'), findsOneWidget);
      expect(find.text('Send to back'), findsOneWidget);

      await tester.tap(find.text('Bring to front'));
      await tester.pump();
      expect(front, 'obj-1');

      await tester.tap(find.bySemanticsLabel('More canvas actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send to back'));
      await tester.pump();
      expect(back, 'obj-1');
    },
  );

  testWidgets(
    'Delete is absent with nothing selected, and fires with an object selected',
    (tester) async {
      await tester.pumpWidget(
        _wrap(_bar(selection: ValueNotifier<String?>(null))),
      );
      await tester.tap(find.bySemanticsLabel('More canvas actions'));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsNothing);

      String? deleted;
      await tester.pumpWidget(
        _wrap(
          _bar(
            selection: ValueNotifier<String?>('obj-1'),
            onDeleteSelected: (id) => deleted = id,
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('More canvas actions'));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pump();
      expect(deleted, 'obj-1');
    },
  );

  testWidgets(
    'clearing goes through a menu, then a confirm naming the count, and '
    'only calls onClear once confirmed',
    (tester) async {
      var cleared = 0;
      await tester.pumpWidget(
        _wrap(
          _bar(
            canManage: true,
            objectCount: ValueNotifier<int>(42),
            onClear: () async => cleared++,
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('More canvas actions'));
      await tester.pumpAndSettle();
      expect(find.text('Clear canvas'), findsOneWidget);
      expect(cleared, 0, reason: 'opening the menu must not clear anything');

      await tester.tap(find.text('Clear canvas'));
      await tester.pumpAndSettle();

      expect(find.text('Clear this canvas?'), findsOneWidget);
      expect(
        find.textContaining('all 42 objects'),
        findsOneWidget,
        reason: 'the confirm must name the live count, not a stale one',
      );
      expect(cleared, 0);

      await tester.tap(find.text('Clear canvas').last);
      await tester.pumpAndSettle();

      expect(cleared, 1);
    },
  );

  testWidgets(
    'the overflow offers to show or hide the activity log, and its label '
    'says which',
    (tester) async {
      var toggled = 0;
      await tester.pumpWidget(
        _wrap(_bar(onToggleActivityLog: () => toggled++)),
      );

      await tester.tap(find.bySemanticsLabel('More canvas actions'));
      await tester.pumpAndSettle();
      expect(find.text('Show activity log'), findsOneWidget);
      expect(find.text('Hide activity log'), findsNothing);

      await tester.tap(find.text('Show activity log'));
      await tester.pump();
      expect(toggled, 1);
    },
  );

  testWidgets('the overflow label flips once the log is open', (tester) async {
    await tester.pumpWidget(_wrap(_bar(activityLogOpen: true)));

    await tester.tap(find.bySemanticsLabel('More canvas actions'));
    await tester.pumpAndSettle();

    expect(find.text('Hide activity log'), findsOneWidget);
    expect(find.text('Show activity log'), findsNothing);
  });

  testWidgets('cancelling the confirm never calls onClear', (tester) async {
    var cleared = 0;
    await tester.pumpWidget(
      _wrap(_bar(canManage: true, onClear: () async => cleared++)),
    );

    await tester.tap(find.bySemanticsLabel('More canvas actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear canvas'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep canvas'));
    await tester.pumpAndSettle();

    expect(cleared, 0);
  });

  /// Every affordance this bar adds - pen, eraser, undo, the overflow, and
  /// the existing close - is a tap target, none of them keyboard-only.
  testWidgets('every new affordance is reachable by touch, at phone width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(_bar(canManage: true, canUndo: true), width: 320),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final label in [
      'Pen',
      'Note',
      'Shape',
      'Eraser',
      'Move',
      'Undo',
      'More canvas actions',
      'Close canvas',
    ]) {
      expect(
        find.bySemanticsLabel(label),
        findsOneWidget,
        reason: '$label must be reachable at the narrowest supported width',
      );
    }
  });

  /// A mouse hover is the only route a sighted desktop user has to learn a
  /// button's name without already knowing the icon, so every button here
  /// needs one - not just a screen-reader-only semantic label.
  testWidgets('every toolbar and overflow button carries a hover tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_bar(canManage: true, canUndo: true)));

    for (final tooltip in [
      'Pen',
      'Note',
      'Undo',
      'More canvas actions',
      'Close canvas',
    ]) {
      expect(
        find.byTooltip(tooltip),
        findsOneWidget,
        reason:
            '$tooltip must be reachable on hover, not only by screen reader',
      );
    }
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message?.startsWith('Move an object') ?? false),
      ),
      findsOneWidget,
      reason: 'Move\'s tooltip is the only place Shift-frees-aspect is said',
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message?.contains('pen ink only') ?? false),
      ),
      findsOneWidget,
      reason: 'Eraser\'s tooltip is the only place its ink-only scope is said',
    );
  });

  /// A disabled control must say why, per the design language: greyed out
  /// with no explanation reads as broken rather than as "nothing to do yet".
  testWidgets('the undo tooltip explains why it is disabled', (tester) async {
    await tester.pumpWidget(_wrap(_bar(canUndo: false)));
    expect(find.byTooltip('Nothing to undo yet'), findsOneWidget);
    expect(find.byTooltip('Undo'), findsNothing);

    await tester.pumpWidget(_wrap(_bar(canUndo: true)));
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Nothing to undo yet'), findsNothing);
  });

  /// The trigger button is already an ordinary tab stop reachable by Tab and
  /// Enter/Space, the same as any other `AppIconButton`; what the message
  /// context menu needed and this lacked is what happens once it is open.
  testWidgets('Escape closes the overflow menu once it is open', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_bar()));

    await tester.tap(find.bySemanticsLabel('More canvas actions'));
    await tester.pumpAndSettle();
    expect(find.text('Paste image'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.text('Paste image'), findsNothing);
  });

  /// Ctrl+V already works from anywhere in the pane; nothing said so until
  /// this hint, which is why it belongs in the one menu item that duplicates
  /// what the shortcut already does.
  testWidgets('Paste image shows a Ctrl+V hint on a pointer layout', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_bar()));

    await tester.tap(find.bySemanticsLabel('More canvas actions'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppKbd, 'Ctrl'), findsOneWidget);
    expect(find.widgetWithText(AppKbd, 'V'), findsOneWidget);
  });

  /// The same "no finger can press it" rule the channel search field's own
  /// Ctrl+K hint already follows. `AppTouchTargets.of` reads the real window
  /// size when nothing overrides it (see its own doc), which a `SizedBox`
  /// constraining only this widget's own render box cannot fake - the
  /// window itself has to shrink, the way `ui_snapshot_test.dart` already
  /// does for exactly this reason.
  testWidgets('the Ctrl+V hint is dropped on a touch layout', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(_bar()));

    await tester.tap(find.bySemanticsLabel('More canvas actions'));
    await tester.pumpAndSettle();

    expect(find.byType(AppKbd), findsNothing);
  });
}
