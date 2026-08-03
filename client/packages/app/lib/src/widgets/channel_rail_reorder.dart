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
  final Widget Function(Channel channel) rowBuilder;
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
              _ChannelItem(:final channel) => rowBuilder(channel),
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
              child: rowBuilder(channel),
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
