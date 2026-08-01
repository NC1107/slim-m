// SPDX-License-Identifier: Apache-2.0
/// Drag-to-reorder for one channel-rail section (text or voice).
///
/// A plain [Column] when nobody may reorder, so an ordinary member's rail is
/// exactly what it always was. [ReorderableListView] takes over only for a
/// manager, nested with [ReorderableListView.shrinkWrap] since the rail's own
/// [ListView] is the one thing that actually scrolls here.
library;

import 'package:flutter/material.dart';
import 'package:slimm_data/data.dart';

/// Renders [channels] as [rowBuilder] built rows, reorderable by [canManage].
///
/// A held drag on any platform starts the move
/// ([ReorderableDelayedDragStartListener]) rather than the library's default
/// (a drag handle glyph on desktop, a long press on mobile with none): the
/// row already carries a manage kebab in its trailing slot, and a second
/// glyph beside it would be one control too many for what a drag already
/// reaches through a held press.
class ReorderableChannelRows extends StatelessWidget {
  const ReorderableChannelRows({
    super.key,
    required this.channels,
    required this.canManage,
    required this.onReorder,
    required this.rowBuilder,
  });

  final List<Channel> channels;
  final bool canManage;

  /// Called with every channel's id, in the new order a drag produced.
  final ValueChanged<List<String>> onReorder;
  final Widget Function(Channel channel) rowBuilder;

  @override
  Widget build(BuildContext context) {
    if (!canManage) {
      return Column(
        children: [for (final channel in channels) rowBuilder(channel)],
      );
    }
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) {
        final order = channels.map((c) => c.id).toList();
        final moved = order.removeAt(oldIndex);
        order.insert(newIndex, moved);
        onReorder(order);
      },
      children: [
        for (var i = 0; i < channels.length; i++)
          ReorderableDelayedDragStartListener(
            key: ValueKey(channels[i].id),
            index: i,
            child: rowBuilder(channels[i]),
          ),
      ],
    );
  }
}
