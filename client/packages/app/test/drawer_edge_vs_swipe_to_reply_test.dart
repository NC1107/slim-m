// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The two horizontal gestures on a compact channel, driven together.
///
/// Neither widget's own test file can show this: `swipe_to_reply_test.dart`
/// mounts the row with no drawer anywhere, and nothing mounted the edge strip
/// over a real transcript at all. Between them the row was split so that the
/// drawer had about four usable pixels - Flutter's `DrawerController` claims
/// the leftmost 20 whether or not it will act on them, the strip ended at 24,
/// and every drag starting past 24 replied to a message. Measured before the
/// fix: start at 2, 6 or 12 did nothing at all, 20 opened the drawer, and 30
/// or 60 fired a reply.
///
/// The owner reported it twice, the second time as still happening: "I swipe
/// to pull open the sidebar and I reply to a message".
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/drawer_edge_swipe.dart';
import 'package:slimm_app/src/widgets/swipe_to_reply.dart';
import 'package:slimm_design_system/design_system.dart';

/// A compact channel in miniature: a drawer, and a transcript of one row that
/// swipes to reply, with the edge strip over it exactly as `home_shell` mounts
/// it.
Widget _harness({required VoidCallback onReply}) => MaterialApp(
  theme: buildTheme(Brightness.light, AppTokens.light),
  home: Scaffold(
    drawer: const Drawer(child: SizedBox()),
    // What home_shell sets, and the half of the fix that hands the edge over.
    drawerEnableOpenDragGesture: false,
    body: DrawerEdgeSwipe(
      child: ListView(
        children: [
          SwipeToReply(
            enabled: true,
            onCommit: onReply,
            child: Container(height: 64, color: Colors.blueGrey),
          ),
        ],
      ),
    ),
  ),
);

/// Drags 120px right from [startX] - well past both the drawer's open
/// distance and the reply threshold - and says what it did.
Future<({bool drawer, int replies})> _dragRight(
  WidgetTester tester,
  double startX,
  int Function() replies,
) async {
  final before = replies();
  final gesture = await tester.startGesture(Offset(startX, 32));
  for (var i = 0; i < 12; i++) {
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
  final state = tester.state<ScaffoldState>(find.byType(Scaffold));
  final result = (drawer: state.isDrawerOpen, replies: replies() - before);
  if (state.isDrawerOpen) {
    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();
  }
  return result;
}

void main() {
  testWidgets('a drag anywhere in the edge zone opens the drawer', (
    tester,
  ) async {
    var replies = 0;
    await tester.pumpWidget(_harness(onReply: () => replies++));
    await tester.pumpAndSettle();

    // Every one of these did nothing at all before the fix except 20.
    for (final startX in [2.0, 6.0, 12.0, 20.0]) {
      final r = await _dragRight(tester, startX, () => replies);
      expect(
        r.drawer,
        isTrue,
        reason:
            'a drag from x=$startX is inside the edge zone, so it belongs '
            'to the drawer',
      );
      expect(
        r.replies,
        0,
        reason: 'and it must not also reply to the message underneath',
      );
    }
  });

  testWidgets('a drag past the edge zone still replies', (tester) async {
    var replies = 0;
    await tester.pumpWidget(_harness(onReply: () => replies++));
    await tester.pumpAndSettle();

    final r = await _dragRight(
      tester,
      kDrawerEdgeZoneWidth + 20,
      () => replies,
    );
    expect(r.drawer, isFalse);
    expect(
      r.replies,
      1,
      reason: 'the fix must not cost the row its reply gesture',
    );
  });

  testWidgets('the edge zone stays clear of the row\'s own avatar', (
    tester,
  ) async {
    // Gutter 10 + avatar 36: a wider zone takes a reply swipe started on the avatar.
    expect(kDrawerEdgeZoneWidth, lessThanOrEqualTo(24));
  });

  testWidgets('a row inside a drawer Scaffold refuses an edge drag on its own', (
    tester,
  ) async {
    // No DrawerEdgeSwipe over it, so only SwipeToReply's own refusal can decline.
    var replies = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          drawer: const Drawer(child: SizedBox()),
          drawerEdgeDragWidth: 0,
          body: ListView(
            children: [
              SwipeToReply(
                enabled: true,
                onCommit: () => replies++,
                child: Container(height: 64, color: Colors.blueGrey),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inZone = await _dragRight(tester, 10, () => replies);
    expect(
      inZone.replies,
      0,
      reason: 'a drag starting in the drawer edge zone is never a reply',
    );

    final outside = await _dragRight(
      tester,
      kDrawerEdgeZoneWidth + 20,
      () => replies,
    );
    expect(outside.replies, 1, reason: 'past the zone it still replies');
  });
}
