// SPDX-License-Identifier: Apache-2.0
/// The channel rail's own edge: click it to collapse or restore the rail.
///
/// Replaced the header's dedicated toggle button once (#256), then replaced
/// drag-to-resize with a plain click (backlog item 54): the owner found the
/// draggable divider's wide hit region read as "a huge resize bar" for a
/// feature that only ever needed to flip a bit, and said he would settle for
/// a toggle. Reads and writes the same [channelRailVisibleProvider] #256
/// already shipped, so nothing about how the collapsed state is stored or
/// restored changes, only how it is reached.
///
/// Backlog item 58: that toggle's own wide hit region then read as a gap
/// nothing could touch - the channel list, the footer's settings button, the
/// transcript all stopped short of the visible line because a Row sibling
/// reserved the room around it. See [_RailHandleHitArea]'s own doc for the
/// fix, and this file's git history for the color-matched-fill approach it
/// replaced (which could not be made correct at the footer, whose own
/// background is a different token from the rest of the rail).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import 'channel_rail.dart';

/// Sits where the rail meets the conversation, at every width that docks the
/// rail beside it (medium and expanded; the compact drawer from #301 is a
/// separate mechanism and never builds this at all).
///
/// The painted line is always a single hairline - [AppTokens.borderSubtle],
/// tinted with [AppTokens.accentFill] on hover for feedback - never a filled
/// bar, which is the visual half of item 54's fix.
///
/// Collapsed, this is the *only* way back: there is no button anywhere else
/// that restores the rail, so it always renders a real, hittable
/// [AppIcons.sidebar] glyph rather than the empty gap a hidden rail would
/// otherwise leave, in a real [AppSizes.rowPointer]/[AppSizes.rowTouch]-wide
/// box - there is no boundary to keep clear of yet, since the rail itself is
/// zero width, so this is a plain reserved [SizedBox] like any other control.
/// `rail_drag_handle_test.dart`'s discoverability test mutation-tests
/// exactly this: hiding the glyph while collapsed is the one failure mode
/// this feature cannot ship with.
///
/// Open, the divider is a single hairline and reserves only that hairline's
/// own width from the `Row` it sits in - [_RailHandleHitArea] is what makes
/// the click/hover region comfortable anyway, by laying the same
/// interactive subtree out wider than that, reaching back (capped at
/// [AppSpacing.s8]) into the rail's own already-blank edge - never into the
/// transcript, where a message row is opaque edge to edge - rather than
/// pushing the rail or the transcript away from the line to make room for
/// itself. [_RailHandleHitArea] wraps [Semantics] rather than sitting
/// inside it, and it has to: the widening only reaches the real
/// [GestureDetector] if it sits above the whole chain, and `Semantics`
/// merges its own render object's reported size with the same chain's, so
/// nesting it the other way would report the wide box back to the `Row` too.
/// The collapsed branch keeps `Semantics` outermost, unlike the open one, so
/// `tester.getSemantics` - which resolves a finder to whatever render
/// object this build() returns directly, falling back to an ancestor only
/// when that object owns no semantics of its own - still finds it directly.
///
/// **"Already-blank" is an assumption this file cannot see enforced.**
/// `channel_rail.dart`'s own row-list `ListView` pins its right inset to
/// this exact same [AppSpacing.s8] (with a comment pointing back here) so a
/// real channel row's own tap target never sits under the widened reach -
/// `rail_drag_handle_test.dart` pins the geometry, since nothing about the
/// type system ties two different files' padding together on its own.
///
/// [GestureDetector] carries `excludeFromSemantics: true`: a real pointer
/// tap needs its own recognizer now that a plain click has to work (it did
/// not before item 54, when only a drag was handled here), but letting it
/// also publish its own tap action bled this control's label onto an
/// unrelated ancestor's - found by dumping the real semantics tree, not by
/// reading the widget, since nothing about the code looked wrong.
///
/// The collapsed icon is coloured [AppTokens.textSecondary], not
/// [AppTokens.borderSubtle] the way the open-state hairline is: it is the
/// *only* way back once the rail is gone, and borderSubtle reads at roughly
/// 1.3:1 against the surface in both themes, well under WCAG 1.4.11's 3:1
/// floor for a UI component boundary, where textSecondary already clears
/// the stricter 4.5:1 AA text floor (`contrast_test.dart`) and so clears
/// this one with room, while staying the same muted, undecorated register.
class RailDragHandle extends ConsumerStatefulWidget {
  const RailDragHandle({super.key});

  @override
  ConsumerState<RailDragHandle> createState() => _RailDragHandleState();
}

class _RailDragHandleState extends ConsumerState<RailDragHandle> {
  bool _hovered = false;

  void _toggle() =>
      ref.read(channelRailVisibleProvider.notifier).update((value) => !value);

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final visible = ref.watch(channelRailVisibleProvider);
    final touch = AppTouchTargets.of(context);
    final hitWidth = touch ? AppSizes.rowTouch : AppSizes.rowPointer;
    final lineColor = _hovered ? tokens.accentFill : tokens.borderSubtle;
    // See this class's own doc for why this is textSecondary, not borderSubtle.
    final iconColor = _hovered ? tokens.accentFill : tokens.textSecondary;

    // See this class's own doc for why Semantics sits where it does below.
    final gestureChain = Semantics(
      button: true,
      label: visible ? 'Collapse channel list' : 'Expand channel list',
      onTap: _toggle,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _toggle(),
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // The real pointer tap; the outer Semantics covers accessibility, see its own doc.
          excludeFromSemantics: true,
          onTap: _toggle,
          child: visible
              ? Row(
                  children: [
                    // The rail's own Container already paints this margin.
                    const Expanded(child: SizedBox()),
                    VerticalDivider(width: 1, color: lineColor),
                  ],
                )
              : SizedBox(
                  width: hitWidth,
                  child: Center(
                    child: Icon(
                      AppIcons.sidebar,
                      size: AppSizes.icon16,
                      color: iconColor,
                    ),
                  ),
                ),
        ),
      ),
    );

    if (!visible) return gestureChain;

    // Capped at AppSpacing.s8 - see this class's own doc for why that's safe.
    final railReach = math.min(hitWidth / 2, AppSpacing.s8);
    return _RailHandleHitArea(
      layoutWidth: 1,
      childWidth: 1 + railReach,
      childOffset: -railReach,
      child: gestureChain,
    );
  }
}

/// Lays [child] out at [childWidth] - wider than what this widget reports
/// for its own layout - so its hit-testable and hoverable area can be
/// comfortable while [layoutWidth] (all a `Row` parent ever sees, and so
/// all it ever reserves) stays the width of the line [RailDragHandle]
/// actually draws.
///
/// This only works because [RenderBox.hitTest]'s own default gates on the
/// box's *reported* [RenderBox.size] before it even asks a child: a `Row`
/// sibling boxed at [layoutWidth] can never be tapped anywhere past it, no
/// matter what an [OverflowBox] or a `Stack` paints there, because that
/// gate runs on every ancestor down to this one first. [hitTest] is
/// overridden to skip straight to [RenderBox.hitTestChildren] instead,
/// which is where [child]'s own (genuinely wider) size takes over - nothing
/// else about hit-testing, focus, or semantics changes, since none of the
/// existing chain reports its own geometry independently of [child]'s.
class _RailHandleHitArea extends SingleChildRenderObjectWidget {
  const _RailHandleHitArea({
    required this.layoutWidth,
    required this.childWidth,
    required this.childOffset,
    required Widget super.child,
  });

  final double layoutWidth;
  final double childWidth;

  /// [child]'s x offset from this widget's own left edge; negative reaches
  /// left, into whatever painted before this one in the same `Row`.
  final double childOffset;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRailHandleHitArea(
        layoutWidth: layoutWidth,
        childWidth: childWidth,
        childOffset: childOffset,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRailHandleHitArea renderObject,
  ) {
    renderObject
      ..layoutWidth = layoutWidth
      ..childWidth = childWidth
      ..childOffset = childOffset;
  }
}

class _RenderRailHandleHitArea extends RenderShiftedBox {
  _RenderRailHandleHitArea({
    required double layoutWidth,
    required double childWidth,
    required double childOffset,
  }) : _layoutWidth = layoutWidth,
       _childWidth = childWidth,
       _childOffset = childOffset,
       super(null);

  double _layoutWidth;
  set layoutWidth(double value) {
    if (_layoutWidth == value) return;
    _layoutWidth = value;
    markNeedsLayout();
  }

  double _childWidth;
  set childWidth(double value) {
    if (_childWidth == value) return;
    _childWidth = value;
    markNeedsLayout();
  }

  double _childOffset;
  set childOffset(double value) {
    if (_childOffset == value) return;
    _childOffset = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child != null) {
      child.layout(
        BoxConstraints.tightFor(
          width: _childWidth,
          height: constraints.maxHeight,
        ),
        parentUsesSize: true,
      );
      (child.parentData! as BoxParentData).offset = Offset(_childOffset, 0);
    }
    size = constraints.constrain(Size(_layoutWidth, constraints.maxHeight));
  }

  /// Deliberately not [RenderBox]'s own default: that checks `size.contains`
  /// first, which is exactly the reserved-width gate this class exists to
  /// route around. [hitTestChildren] still checks [child]'s own, genuinely
  /// wider, size on the way down - nothing is hit outside that.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      hitTestChildren(result, position: position);
}
