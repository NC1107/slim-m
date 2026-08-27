// SPDX-License-Identifier: Apache-2.0
/// The scrollable body shared by sheets that list a bounded-but-growing
/// per-channel set (`pinned_messages_sheet.dart`, `threads_sheet.dart`):
/// each sits inside a `ConstrainedBox(maxHeight: ...)` and wants a short
/// list to shrink to its own content rather than always claiming that
/// ceiling.
///
/// `ListView.builder(shrinkWrap: true)` gets that sizing from a
/// `ShrinkWrappingViewport`, which has to lay out every child up front to
/// learn its own total extent - unlike a bounded viewport, which only lays
/// out whatever is actually on screen. That is fine for a handful of rows,
/// but a channel can hold up to `MAX_PINS_PER_CHANNEL` /
/// `MAX_THREADS_PER_CHANNEL` of them, and a live pin/thread event rebuilds
/// the sheet while it is open: paying a full relayout of the whole backlog
/// on every such event is the actual cost, not the list's fixed ceiling.
/// Past [sheetListShrinkWrapLimit] this switches to a plain bounded
/// `ListView`, which fills the same ceiling but only ever lays out the rows
/// on screen, however large the underlying set grows.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// Item counts at or under this shrink-wrap to their own content; a plain
/// bounded list past it. Comfortably above what fits on screen at any
/// shipped resolution, so an ordinary short list is unaffected.
const int sheetListShrinkWrapLimit = 24;

/// A sheet's list body: shrink-wrapped under [sheetListShrinkWrapLimit]
/// items, a plain bounded [ListView.builder] at or above it. Both share the
/// same padding, so the switch never visibly shifts a row's content.
class SheetItemList extends StatelessWidget {
  const SheetItemList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: itemCount <= sheetListShrinkWrapLimit,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}
