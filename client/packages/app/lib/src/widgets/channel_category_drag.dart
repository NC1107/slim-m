// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Dragging a whole category header to reorder categories (design review
/// note 8): the header's own grip ([CategoryDragGrip]) is the drag source,
/// and every header ([CategoryDragTarget]) is a drop target - entirely
/// separate from `channel_rail_reorder.dart`'s own flat
/// `ReorderableListView`, which only ever moves individual channel rows and
/// explicitly ignores anything else dropped on it (`moved is!
/// ChannelRailItem`). Reordering categories through that list would risk the
/// exact channel-reassignment hazard `category_reorder.dart` once existed to
/// avoid, so this drags with plain `Draggable`/`DragTarget` instead:
/// reordering the category list alone never touches which channel belongs to
/// which category, so every channel travels with its own header for free
/// the moment the category order changes and the rail rebuilds from it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/channel_order_controller.dart';
import 'rail_drag_lift.dart';

/// The grip that starts a category drag - a dedicated handle rather than the
/// whole header, so the header's own right-click menu and (once note 2
/// lands) tap-to-fold never contest the same gesture the way a whole-row
/// listener would.
///
/// [Draggable.dragAnchorStrategy] is [pointerDragAnchorStrategy], not the
/// default: [CategoryDragTarget] reads `DragTargetDetails.offset` to tell
/// which half of a header a drop lands in, and that only lines up with the
/// cursor under this strategy - the default anchors the feedback, and so the
/// reported offset, to wherever within the grip the drag started instead.
class CategoryDragGrip extends StatelessWidget {
  const CategoryDragGrip({super.key, required this.category});

  final ChannelCategoryRow category;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final glyph = Icon(
      AppIcons.dragHandle,
      size: AppSizes.icon16,
      color: tokens.textSecondary,
    );
    return Draggable<String>(
      data: category.id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // Already fully lifted: a Draggable feedback has no proxy animation controller for RailDragLift to follow.
      feedback: RailDragLift(
        animation: kAlwaysCompleteAnimation,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s8,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              category.name,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(color: tokens.textPrimary),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: glyph),
      child: Semantics(label: 'Reorder ${category.name}', child: glyph),
    );
  }
}

/// Where a hovered drag would land relative to the header underneath it.
enum _DropSide { before, after }

/// Wraps one category header ([child]) as a drop target for another
/// category's [CategoryDragGrip]. A `null` [category] - the implicit
/// uncategorised section - never accepts a drop: it has no id to reorder
/// among.
class CategoryDragTarget extends ConsumerStatefulWidget {
  const CategoryDragTarget({
    super.key,
    required this.category,
    required this.ordered,
    required this.child,
  });

  final ChannelCategoryRow? category;

  /// Every real category, in the order the rail currently shows them.
  final List<ChannelCategoryRow> ordered;
  final Widget child;

  @override
  ConsumerState<CategoryDragTarget> createState() => _CategoryDragTargetState();
}

class _CategoryDragTargetState extends ConsumerState<CategoryDragTarget> {
  _DropSide? _hoverSide;

  Future<void> _drop(
    String draggedId,
    ChannelCategoryRow onto,
    _DropSide side,
  ) async {
    final ids = [for (final c in widget.ordered) c.id];
    final from = ids.indexOf(draggedId);
    if (from < 0) return;
    ids.removeAt(from);
    var to = ids.indexOf(onto.id);
    if (side == _DropSide.after) to += 1;
    ids.insert(to.clamp(0, ids.length), draggedId);
    await ref.read(categoryOrderControllerProvider.notifier).reorder(ids);
  }

  _DropSide _sideFor(Offset globalPosition) {
    final box = context.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(globalPosition);
    return local.dy < box.size.height / 2 ? _DropSide.before : _DropSide.after;
  }

  Widget _withDropLine(Widget child) {
    final side = _hoverSide;
    if (side == null) return child;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          top: side == _DropSide.before ? 0 : null,
          bottom: side == _DropSide.after ? 0 : null,
          child: Container(height: 2, color: tokens.accent),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    if (category == null) return _withDropLine(widget.child);

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != category.id,
      onMove: (details) {
        final side = _sideFor(details.offset);
        if (side != _hoverSide) setState(() => _hoverSide = side);
      },
      onLeave: (_) => setState(() => _hoverSide = null),
      onAcceptWithDetails: (details) {
        final side = _hoverSide ?? _DropSide.before;
        setState(() => _hoverSide = null);
        unawaited(_drop(details.data, category, side));
      },
      builder: (context, candidates, rejected) => _withDropLine(widget.child),
    );
  }
}
