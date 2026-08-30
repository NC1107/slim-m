// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The categories screen's own drag-to-reorder list, split out of
/// `categories_screen.dart` for the review budget.
///
/// This is deliberately a second, separate reorderable list rather than
/// reusing `channel_rail_reorder.dart`'s `ReorderableChannelRows`: that
/// widget's flat single list attributes every channel to whichever header
/// precedes it, so dragging a whole category block through it would risk
/// silently reassigning the channels it passed over on the way. This screen
/// has no channels in it at all - only categories - so a drag here can only
/// ever mean "these are the categories, in this order", with none of that
/// risk.
library;

import 'package:flutter/material.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

/// Renders [pending] (a reorder this client is waiting on, or has just had
/// refused) over [categories], the same "show the optimistic arrangement
/// rather than what the store still holds" shape `channel_rail.dart`'s own
/// `_withPendingOrder` uses for channels.
List<ChannelCategoryRow> withPendingCategoryOrder(
  List<ChannelCategoryRow> categories,
  List<String>? pending,
) {
  if (pending == null) return categories;
  final byId = {for (final category in categories) category.id: category};
  final named = <ChannelCategoryRow>[
    for (final id in pending)
      if (byId[id] case final category?) category,
  ];
  final namedIds = named.map((c) => c.id).toSet();
  return [
    ...named,
    for (final category in categories)
      if (!namedIds.contains(category.id)) category,
  ];
}

/// The categories list, drag-reorderable once there are at least two of
/// them - with fewer, there is nothing a drag could ever reorder, the same
/// bail-out `ReorderableChannelRows` uses (`channel_rail_reorder.dart`).
///
/// [rowBuilder] is told this render's own position for the row, or null when
/// there is nothing to reorder - the same "am I actually wrapped in a drag
/// listener this render" shape `ReorderableChannelRows.rowBuilder` already
/// uses, so a caller decides whether to draw [CategoryDragHandle] rather
/// than this widget assuming it always should. A whole-row held press (the
/// channel row precedent) is deliberately not used here: a category row's
/// primary content is an editable `AppInput`, whose own long-press starts
/// text selection at essentially the same hold duration a delayed drag
/// listener would use, so wrapping the whole row would risk the identical
/// gesture-arena race PR #564 found between a context menu's long press and
/// a reorder listener - a different competitor, the same shape. Neither this
/// screen's rows nor the rail's own category headers carry a
/// `ContextMenuRegion`, so that specific collision does not recur here.
class CategoryList extends StatelessWidget {
  const CategoryList({
    super.key,
    required this.categories,
    required this.onReorder,
    required this.rowBuilder,
  });

  final List<ChannelCategoryRow> categories;

  /// Called with every category's id, in the arrangement a drag produced,
  /// once it settles.
  final ValueChanged<List<String>> onReorder;

  /// Builds one category's row, given its own position in the list this
  /// render actually wraps in a drag listener - null in the plain-[Column]
  /// branch, an index in the [ReorderableListView] one.
  final Widget Function(ChannelCategoryRow category, int? dragIndex) rowBuilder;

  @override
  Widget build(BuildContext context) {
    if (categories.length < 2) {
      return Column(
        children: [
          for (final category in categories) rowBuilder(category, null),
        ],
      );
    }
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) {
        final ids = [for (final category in categories) category.id];
        ids.insert(newIndex, ids.removeAt(oldIndex));
        onReorder(ids);
      },
      children: [
        for (var i = 0; i < categories.length; i++)
          KeyedSubtree(
            key: ValueKey(categories[i].id),
            child: rowBuilder(categories[i], i),
          ),
      ],
    );
  }
}

/// A dedicated grab zone before a category row's own name field - see
/// [CategoryList]'s own doc comment for why this is not the channel row's
/// whole-row held press. Immediate rather than delayed: nothing else in the
/// row's leading edge competes for the same press, so there is no arena to
/// wait out.
class CategoryDragHandle extends StatelessWidget {
  const CategoryDragHandle({
    super.key,
    required this.index,
    required this.name,
  });

  final int index;
  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final touch = AppTouchTargets.of(context);
    final size = touch ? AppSizes.rowTouch : AppSizes.rowPointer;
    return ReorderableDragStartListener(
      index: index,
      child: Semantics(
        label: 'Reorder $name',
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(
              AppIcons.dragHandle,
              size: AppSizes.icon16,
              color: tokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
