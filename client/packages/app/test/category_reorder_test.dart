// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Tests for `CategoryList`/`CategoryDragHandle`: fewer than two categories
/// draws no handle at all, a real drag reports the new arrangement in the
/// right order, and the handle carries a real accessible name - see
/// `categories_screen.dart`'s own doc comment for why this is a second,
/// separate reorderable list rather than the rail's `ReorderableChannelRows`.
///
/// The accessible-name test reads `find.bySemanticsLabel` rather than
/// `tester.getSemantics(find.byType(CategoryDragHandle))`, because the two
/// are not equivalent here: `WidgetTester.getSemantics` walks upward from
/// the found element's own render object toward the root looking for a
/// `debugSemantics` answer, it never descends into a child. The element
/// `find.byType(CategoryDragHandle)` locates resolves to `Listener` (from
/// `ReorderableDragStartListener`), which owns no semantics node of its
/// own and sits *above* the `Semantics(label: ...)` wrapping the handle's
/// `SizedBox` in the real widget tree - a descendant `getSemantics` cannot
/// reach by walking up. `find.bySemanticsLabel` reads the compiled tree
/// directly instead and has no such blind spot.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/admin/category_reorder.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

ChannelCategoryRow _category(String id, int position) =>
    ChannelCategoryRow(id: id, name: id, position: position);

Widget _harness(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.light, AppTokens.light),
  home: Scaffold(body: SizedBox(height: 400, child: child)),
);

void main() {
  test('withPendingCategoryOrder renders null pending as the store order', () {
    final categories = [_category('a', 0), _category('b', 1)];
    expect(withPendingCategoryOrder(categories, null), categories);
  });

  test('withPendingCategoryOrder renders a pending arrangement, keeping any '
      'category the drag did not name at the end in its stored order', () {
    final categories = [
      _category('a', 0),
      _category('b', 1),
      _category('c', 2),
    ];
    final result = withPendingCategoryOrder(categories, ['b', 'a']);
    expect(
      result.map((c) => c.id),
      ['b', 'a', 'c'],
      reason:
          'the drag reordered a and b; c was not part of that drag and '
          'keeps trailing after them',
    );
  });

  testWidgets('fewer than two categories draws no drag handle', (tester) async {
    var reported = false;
    await tester.pumpWidget(
      _harness(
        CategoryList(
          categories: [_category('a', 0)],
          onReorder: (_) => reported = true,
          rowBuilder: (category, dragIndex) {
            expect(dragIndex, isNull);
            return Text(category.id);
          },
        ),
      ),
    );

    expect(find.byType(ReorderableListView), findsNothing);
    expect(find.byType(CategoryDragHandle), findsNothing);
    expect(reported, isFalse);
  });

  testWidgets(
    'a real drag on the handle reports the categories in the new order, '
    'not just that a widget moved',
    (tester) async {
      List<String>? reported;
      await tester.pumpWidget(
        _harness(
          CategoryList(
            categories: [
              _category('a', 0),
              _category('b', 1),
              _category('c', 2),
            ],
            onReorder: (ids) => reported = ids,
            rowBuilder: (category, dragIndex) {
              expect(dragIndex, isNotNull);
              return SizedBox(
                height: 48,
                child: Row(
                  children: [
                    CategoryDragHandle(index: dragIndex!, name: category.id),
                    Text(category.id),
                  ],
                ),
              );
            },
          ),
        ),
      );

      // Immediate, not delayed like the rail's whole-row listener - no held-press wait.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CategoryDragHandle).first),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, 100));
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
    },
  );

  testWidgets('the handle carries a real accessible name', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _harness(CategoryDragHandle(index: 0, name: 'Announcements')),
    );

    // See this file's own library doc comment for why not tester.getSemantics.
    expect(find.bySemanticsLabel('Reorder Announcements'), findsOneWidget);
    handle.dispose();
  });
}
