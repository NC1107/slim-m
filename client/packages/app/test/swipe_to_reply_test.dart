// SPDX-License-Identifier: Apache-2.0
/// Coverage for [SwipeToReply]'s own gesture layer, independent of the row
/// it wraps in production: the threshold boundary, that a vertical scroll
/// through it still scrolls the list rather than the row, that a desktop
/// mouse drag never moves anything at all, and that its one release
/// animation honours reduce-motion.
///
/// `message_context_menu_scroll_test.dart` is the sibling this file follows
/// the shape of, for the same reason: a plain "it opened" test cannot prove
/// a gesture actually shares its arena correctly with a real [Scrollable].
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/swipe_to_reply.dart';
import 'package:slimm_design_system/design_system.dart';

/// Wraps [child] in the real theme [SwipeToReply] reads its tokens from, and
/// - only when a caller cares - a [MediaQuery] carrying the reduce-motion
/// signal [AppMotion.reduced] reads.
Widget _harness(Widget child, {MediaQueryData? mediaQuery}) => MaterialApp(
  theme: buildTheme(Brightness.light, AppTokens.light),
  home: Scaffold(
    body: mediaQuery == null
        ? child
        : MediaQuery(data: mediaQuery, child: child),
  ),
);

/// A plain, opaque, fixed-size row - what [SwipeToReply] wraps in production
/// is `MessageContextMenuRegion`, but nothing this file asserts on needs a
/// real message row, only something with a stable size and position to read
/// [WidgetTester.getTopLeft] against before and after a drag.
///
/// [key] goes on the *child*, not on [SwipeToReply] itself: the wrapper's
/// own render object is the [GestureDetector]/[Stack] pair, which
/// `Transform.translate` never moves - only the child it paints shifts, so a
/// key on the wrapper would read the same position no matter what the
/// gesture did, the exact "mutation that kills nothing" shape this
/// codebase's own CI conventions warn about.
Widget _row({
  Key? key,
  required bool enabled,
  required VoidCallback onCommit,
}) => SwipeToReply(
  enabled: enabled,
  onCommit: onCommit,
  child: Container(key: key, height: 64, color: Colors.blueGrey),
);

const _rowKey = ValueKey('row');

void main() {
  testWidgets(
    'a touch swipe one pixel short of the threshold commits nothing on '
    'release',
    (tester) async {
      var commits = 0;
      await tester.pumpWidget(
        _harness(_row(key: _rowKey, enabled: true, onCommit: () => commits++)),
      );

      await tester.drag(
        find.byKey(_rowKey),
        const Offset(swipeToReplyThreshold - 1, 0),
        touchSlopX: 0,
        touchSlopY: 0,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();

      expect(commits, 0);
    },
  );

  testWidgets(
    'a touch swipe that reaches exactly the threshold commits once on '
    'release',
    (tester) async {
      var commits = 0;
      await tester.pumpWidget(
        _harness(_row(key: _rowKey, enabled: true, onCommit: () => commits++)),
      );

      await tester.drag(
        find.byKey(_rowKey),
        const Offset(swipeToReplyThreshold, 0),
        touchSlopX: 0,
        touchSlopY: 0,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();

      expect(commits, 1);
    },
  );

  testWidgets('a swipe carried well past the threshold before releasing still '
      'commits once, not once per pixel travelled', (tester) async {
    var commits = 0;
    await tester.pumpWidget(
      _harness(_row(key: _rowKey, enabled: true, onCommit: () => commits++)),
    );

    await tester.drag(
      find.byKey(_rowKey),
      const Offset(swipeToReplyThreshold * 3, 0),
      touchSlopX: 0,
      touchSlopY: 0,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    expect(commits, 1);
  });

  testWidgets('a desktop mouse drag never moves the row or commits a reply', (
    tester,
  ) async {
    var commits = 0;
    await tester.pumpWidget(
      _harness(_row(key: _rowKey, enabled: true, onCommit: () => commits++)),
    );
    final before = tester.getTopLeft(find.byKey(_rowKey));

    await tester.drag(
      find.byKey(_rowKey),
      const Offset(swipeToReplyThreshold * 2, 0),
      touchSlopX: 0,
      touchSlopY: 0,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(commits, 0);
    expect(
      tester.getTopLeft(find.byKey(_rowKey)),
      before,
      reason:
          'a mouse-originated drag must never shift the row, not even '
          'part-way, since nothing here reads mouse movement at all',
    );
  });

  testWidgets(
    'a disabled row swipes for nothing, even on an otherwise-committing '
    'touch drag',
    (tester) async {
      var commits = 0;
      await tester.pumpWidget(
        _harness(_row(key: _rowKey, enabled: false, onCommit: () => commits++)),
      );
      final before = tester.getTopLeft(find.byKey(_rowKey));

      await tester.drag(
        find.byKey(_rowKey),
        const Offset(swipeToReplyThreshold * 2, 0),
        touchSlopX: 0,
        touchSlopY: 0,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();

      expect(commits, 0);
      expect(tester.getTopLeft(find.byKey(_rowKey)), before);
    },
  );

  testWidgets(
    'a vertical drag over a row still scrolls the list around it, rather '
    'than being swallowed by the horizontal recognizer',
    (tester) async {
      var commits = 0;
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          ListView(
            controller: controller,
            children: [
              for (var i = 0; i < 30; i++)
                _row(
                  key: ValueKey('row-$i'),
                  enabled: true,
                  onCommit: () => commits++,
                ),
            ],
          ),
        ),
      );

      await tester.drag(
        find.byKey(const ValueKey('row-5')),
        const Offset(0, -300),
        kind: PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();

      expect(
        controller.offset,
        greaterThan(0),
        reason:
            'the list has to have actually scrolled for the assertion '
            'below to prove anything about what the row itself did while '
            'it did',
      );
      expect(commits, 0);
    },
  );

  testWidgets('the release snap-back collapses into the same frame under '
      'reduce-motion, rather than animating over several', (tester) async {
    await tester.pumpWidget(
      _harness(
        _row(key: _rowKey, enabled: true, onCommit: () {}),
        mediaQuery: const MediaQueryData(disableAnimations: true),
      ),
    );
    final restingLeft = tester.getTopLeft(find.byKey(_rowKey)).dx;

    await tester.drag(
      find.byKey(_rowKey),
      const Offset(swipeToReplyThreshold - 10, 0),
      touchSlopX: 0,
      touchSlopY: 0,
      kind: PointerDeviceKind.touch,
    );
    // One bare pump: enough for a synchronous jump, not a multi-frame animation.
    await tester.pump();

    expect(tester.getTopLeft(find.byKey(_rowKey)).dx, restingLeft);
  });

  testWidgets('the same release is still mid-animation one frame later without '
      'reduce-motion, which is what makes the case above mean anything', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(_row(key: _rowKey, enabled: true, onCommit: () {})),
    );
    final restingLeft = tester.getTopLeft(find.byKey(_rowKey)).dx;

    await tester.drag(
      find.byKey(_rowKey),
      const Offset(swipeToReplyThreshold - 10, 0),
      touchSlopX: 0,
      touchSlopY: 0,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();

    expect(
      tester.getTopLeft(find.byKey(_rowKey)).dx,
      greaterThan(restingLeft),
      reason:
          'a fast-frame equality here would mean the previous test '
          'proved nothing about reduce-motion specifically',
    );

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_rowKey)).dx, restingLeft);
  });
}
