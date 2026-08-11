// SPDX-License-Identifier: Apache-2.0
/// Drag-to-reorder across the whole channel-rail listing: every category
/// section in one list, so a channel of any kind can be dragged into any
/// category - the property backlog item #34 asked for. See
/// docs/decisions/0006-channel-categories.md.
///
/// A plain [Column] when nobody may reorder, so an ordinary member's rail is
/// exactly what it always was. [ReorderableListView] takes over only for a
/// manager, with every category's header and channel rows as one flat item
/// list: that is what lets a drag cross a section boundary at all, since
/// Flutter's [ReorderableListView] only ever reorders within itself, never
/// between two separate instances.
///
/// Fewer than two channels anywhere in the rail also falls back to the plain
/// column: there is nothing a drag could ever reorder, and it sidesteps a
/// real layout defect found directly against this widget - a
/// [ReorderableListView] holding exactly one item (a lone header, with no
/// channel wrapped in a drag listener at all) reports the right semantics
/// but hit-tests a tap on it to the wrong render object, gone the moment a
/// second item is present.
///
/// **A held drag's own settle animation does not honour `AppMotion` or the
/// real OS reduce-motion toggle, and this is a closed, verified Flutter
/// limitation rather than an open item.** Read against the pinned SDK's own
/// source (`packages/flutter/lib/src/widgets/reorderable_list.dart` and
/// `.../material/reorderable_list.dart`, Flutter 3.44.8) before touching this
/// again: neither `ReorderableListView` nor `SliverReorderableList` exposes
/// an `AnimationStyle` parameter at all, unlike roughly a dozen sibling
/// Material widgets in the same SDK (`Chip`, `Dialog`, `BottomSheet`,
/// `ExpansionTile`, `PopupMenuButton`, `Scaffold`, among others). The 250ms
/// ease-in-out an item takes to slide out of a dragged item's way
/// (`_ReorderableItemState.updateForGap`) is called with `animate: true` from
/// exactly one private, hardcoded call site with no callback or theme
/// extension reaching it, and the drag proxy's own 250ms elevation fade
/// (`_DragInfo.startDrag`) is the same shape. Neither reads
/// `MediaQuery.disableAnimationsOf` or `accessibleNavigationOf` anywhere, so
/// the "self-reduces under real OS-level reduce motion" claim an earlier pass
/// made about this widget does not hold under the source - what actually is
/// accessibility-aware is a different path entirely: a screen reader in use
/// (`accessibleNavigation`) makes Flutter attach custom semantic actions
/// (move to start/before/after/end) that call `onReorderItem` directly with
/// no drag and no animation at all, which is a real and correct fallback but
/// is gated on a screen reader being active, not on the reduce-motion toggle
/// a sighted low-motion user would set. A global `package:flutter/scheduler`
/// `timeDilation` override was considered and rejected: it would reach the
/// same result for this one widget only by scaling every animation in the
/// whole app, including the busy-spinner exception `app_motion.dart`'s own
/// doc comment already carves out on purpose. Closing this for real needs a
/// vendored or forked reorder implementation, which this pass does not do.
///
/// **The drag could never actually start, on any platform, until the
/// `reorderable` flag on [rowBuilder] existed.** `ManagedChannelRow` wraps
/// every channel row in `ContextMenuRegion`, whose own long press
/// (`Open channel`/`Manage channel...`) and `ReorderableDelayedDragStartListener`'s
/// own held-press drag start are both a bare hold with no movement, timed
/// against the same `kLongPressTimeout` window - two recognizers racing the
/// identical gesture, and the context menu won every time this was driven
/// through a real `startGesture`/`moveBy` sequence, on both a phone-width
/// drawer and a docked desktop rail. Reported as "can't reorganize channels
/// on mobile" because a phone has no fallback (no right-click); it was
/// exactly as broken at desktop width, just harder to notice with a
/// right-click sitting right there as an alternate route to the same menu.
/// `rowBuilder`'s new second argument is what a caller uses to withhold the
/// context menu's own long press exactly where, and only where, a row is
/// actually wrapped in the drag listener that would otherwise lose to it -
/// see `ManagedChannelRow`'s own `enableLongPress` wiring.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' show ChannelOrderGroup;
import 'package:slimm_data/data.dart';

/// One category's ordered channels, `null` for the implicit uncategorised
/// section, which always renders first.
typedef ChannelSection = (ChannelCategoryRow? category, List<Channel> channels);

sealed class _RailItem {
  const _RailItem();
}

class _HeaderItem extends _RailItem {
  const _HeaderItem(this.category);
  final ChannelCategoryRow? category;
}

class _ChannelItem extends _RailItem {
  const _ChannelItem(this.channel);
  final Channel channel;
}

/// Renders [sections] as [rowBuilder]-built rows under [headerBuilder]-built
/// headers, reorderable across every section by [canManage].
///
/// A held drag on any platform starts the move
/// ([ReorderableDelayedDragStartListener]) rather than the library's default
/// (a drag handle glyph on desktop, a long press on mobile with none): the
/// row already carries a manage kebab in its trailing slot, and a second
/// glyph beside it would be one control too many for what a drag already
/// reaches through a held press. Only channel rows carry that listener, so a
/// header can never itself be picked up, however its slot may still shift as
/// channels are dropped around it.
class ReorderableChannelRows extends StatelessWidget {
  const ReorderableChannelRows({
    super.key,
    required this.sections,
    required this.canManage,
    required this.onReorder,
    required this.rowBuilder,
    required this.headerBuilder,
  });

  final List<ChannelSection> sections;
  final bool canManage;

  /// Called with the whole rail's new arrangement, grouped by category, once
  /// a drag settles.
  final ValueChanged<List<ChannelOrderGroup>> onReorder;

  /// Builds one channel's row, told whether *this render* actually wraps it
  /// in a drag listener - false in the plain-[Column] branch, true in the
  /// [ReorderableListView] one - so a caller can withhold a competing
  /// long-press gesture (a context menu, say) only where one would actually
  /// compete for the arena.
  final Widget Function(Channel channel, bool reorderable) rowBuilder;
  final Widget Function(ChannelCategoryRow? category) headerBuilder;

  List<_RailItem> get _items => [
    for (final (category, channels) in sections) ...[
      _HeaderItem(category),
      for (final channel in channels) _ChannelItem(channel),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final channelCount = items.whereType<_ChannelItem>().length;
    // See this file's own doc comment for why fewer than two also bails out.
    if (!canManage || channelCount < 2) {
      return Column(
        children: [
          for (final item in items)
            switch (item) {
              _HeaderItem(:final category) => headerBuilder(category),
              _ChannelItem(:final channel) => rowBuilder(channel, false),
            },
        ],
      );
    }
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) {
        final moved = items[oldIndex];
        if (moved is! _ChannelItem) return;
        final rearranged = [...items]
          ..removeAt(oldIndex)
          ..insert(newIndex, moved);
        onReorder(_groupsFrom(rearranged, sections));
      },
      children: [
        for (var i = 0; i < items.length; i++)
          switch (items[i]) {
            _HeaderItem(:final category) => KeyedSubtree(
              key: ValueKey('header-${category?.id}'),
              child: headerBuilder(category),
            ),
            _ChannelItem(:final channel) => ReorderableDelayedDragStartListener(
              key: ValueKey(channel.id),
              index: i,
              child: rowBuilder(channel, true),
            ),
          },
      ],
    );
  }
}

/// Walks [items] in order, attributing every channel to whichever header
/// last preceded it, and answers one [ChannelOrderGroup] per section named
/// in [sections] - including one with no channels left, so a drag that
/// empties a category still tells the server to clear it rather than
/// leaving its old contents unmentioned.
List<ChannelOrderGroup> _groupsFrom(
  List<_RailItem> items,
  List<ChannelSection> sections,
) {
  final byCategory = <String?, List<String>>{
    for (final (category, _) in sections) category?.id: [],
  };
  String? current;
  for (final item in items) {
    switch (item) {
      case _HeaderItem(:final category):
        current = category?.id;
      case _ChannelItem(:final channel):
        (byCategory[current] ??= []).add(channel.id);
    }
  }
  return [
    for (final (category, _) in sections)
      ChannelOrderGroup(
        categoryId: category?.id,
        channelIds: byCategory[category?.id] ?? const [],
      ),
  ];
}
