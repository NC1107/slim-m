// SPDX-License-Identifier: Apache-2.0
/// Tests for `ReorderableChannelRows`: no drag at all for an ordinary
/// member, and a completed drag reporting the new id order for a manager.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/channel_rail_reorder.dart';
import 'package:slimm_data/data.dart';

Channel _channel(String id) => Channel(
  id: id,
  name: id,
  kind: 'text',
  createdAt: 0,
  position: 0,
  cursor: 0,
  lastReadSeq: 0,
  isPersonalSpace: false,
);

Widget _harness(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(height: 400, child: child)),
);

void main() {
  testWidgets('a non-manager sees a plain, non-reorderable column', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        ReorderableChannelRows(
          channels: [_channel('a'), _channel('b')],
          canManage: false,
          onReorder: (_) => fail('must not be reachable without canManage'),
          rowBuilder: (channel) => Text(channel.id),
        ),
      ),
    );

    expect(find.byType(ReorderableListView), findsNothing);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('a manager can drag a row to a new position', (tester) async {
    List<String>? reported;
    await tester.pumpWidget(
      _harness(
        ReorderableChannelRows(
          channels: [_channel('a'), _channel('b'), _channel('c')],
          canManage: true,
          onReorder: (order) => reported = order,
          rowBuilder: (channel) =>
              SizedBox(height: 48, child: Text(channel.id)),
        ),
      ),
    );

    // A held press starts the drag; no drag-handle glyph is built at all.
    final gesture = await tester.startGesture(tester.getCenter(find.text('a')));
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await gesture.moveBy(const Offset(0, 120));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(reported, isNotNull);
    expect(
      reported,
      isNot(['a', 'b', 'c']),
      reason: 'the drag must have reported a real reordering',
    );
    expect(reported!.toSet(), {
      'a',
      'b',
      'c',
    }, reason: 'the same three ids, just reordered');
  });
}
