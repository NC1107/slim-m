// SPDX-License-Identifier: Apache-2.0
/// Tests for `ReorderableChannelRows`: no drag at all for an ordinary
/// member, a completed drag within one section reporting the new order, and
/// - the property backlog item #34 asked for - a drag across two category
/// sections reassigning the dragged channel's category. See
/// docs/decisions/0006-channel-categories.md.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' show ChannelOrderGroup;
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

Widget _header(ChannelCategoryRow? category) =>
    Text('header:${category?.id ?? 'uncategorised'}');

void main() {
  testWidgets('a non-manager sees a plain, non-reorderable column', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        ReorderableChannelRows(
          sections: [
            (null, [_channel('a'), _channel('b')]),
          ],
          canManage: false,
          onReorder: (_) => fail('must not be reachable without canManage'),
          rowBuilder: (channel) => Text(channel.id),
          headerBuilder: _header,
        ),
      ),
    );

    expect(find.byType(ReorderableListView), findsNothing);
    expect(find.text('header:uncategorised'), findsOneWidget);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('a manager can drag a row to a new position within a section', (
    tester,
  ) async {
    List<ChannelOrderGroup>? reported;
    await tester.pumpWidget(
      _harness(
        ReorderableChannelRows(
          sections: [
            (null, [_channel('a'), _channel('b'), _channel('c')]),
          ],
          canManage: true,
          onReorder: (order) => reported = order,
          rowBuilder: (channel) =>
              SizedBox(height: 48, child: Text(channel.id)),
          headerBuilder: _header,
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
    expect(reported!.single.categoryId, isNull);
    expect(
      reported!.single.channelIds,
      isNot(['a', 'b', 'c']),
      reason: 'the drag must have reported a real reordering',
    );
    expect(
      reported!.single.channelIds.toSet(),
      {'a', 'b', 'c'},
      reason: 'the same three ids, just reordered',
    );
  });

  testWidgets(
    'a drag across two category sections reassigns the channel to the '
    'section it was dropped in',
    (tester) async {
      final category = ChannelCategoryRow(
        id: 'voice-cat',
        name: 'Voice',
        position: 0,
      );
      List<ChannelOrderGroup>? reported;
      await tester.pumpWidget(
        _harness(
          ReorderableChannelRows(
            sections: [
              (null, [_channel('a')]),
              (category, [_channel('b')]),
            ],
            canManage: true,
            onReorder: (order) => reported = order,
            rowBuilder: (channel) =>
                SizedBox(height: 48, child: Text(channel.id)),
            headerBuilder: _header,
          ),
        ),
      );

      // Drag 'a' down past the "Voice" header and 'b', into the Voice section.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('a')),
      );
      await tester.pump(kLongPressTimeout + kPressTimeout);
      await gesture.moveBy(const Offset(0, 200));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(reported, isNotNull);
      final uncategorised = reported!.firstWhere((g) => g.categoryId == null);
      final voice = reported!.firstWhere((g) => g.categoryId == 'voice-cat');
      expect(
        uncategorised.channelIds.contains('a'),
        isFalse,
        reason: 'dragged out of the uncategorised section',
      );
      expect(
        voice.channelIds.contains('a'),
        isTrue,
        reason: 'a channel of any kind may be dragged into any category',
      );
    },
  );
}
