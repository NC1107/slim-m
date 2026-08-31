// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A horizontal swipe on a message row starts a reply to it - the one-handed
/// gesture every comparable mobile messaging app offers - reached here by an
/// ordinary [GestureDetector.onHorizontalDragStart]/`Update`/`End` trio
/// rather than the raw [Listener] `canvas_surface_gestures.dart` hand-rolls
/// its own pointer routing through.
///
/// The canvas has to hand-roll dispatch because one surface there juggles
/// several simultaneous, same-shaped interactions (a grab-pan, a multi-touch
/// pinch, per-tool placement) the gesture arena cannot tell apart on its
/// own. This widget adds exactly one more recognizer to an arena that
/// already resolves its two neighbours correctly by itself:
/// [HorizontalDragGestureRecognizer] only claims victory once movement
/// passes the touch slop *on the horizontal axis*, so the transcript's own
/// vertical [Scrollable] (claiming on the vertical axis) is never a
/// candidate for the same gesture, and `MessageContextMenuRegion`'s long
/// press (a [LongPressGestureRecognizer], which self-rejects the moment its
/// pointer drifts past `PrimaryPointerGestureRecognizer.preAcceptSlopTolerance`
/// - the framework's own default `kTouchSlop` - before its own deadline
/// fires) loses to a real swipe automatically. That is a different shape
/// from the one `channel_rail_reorder.dart` had to solve with its own
/// `enableLongPress` override: there, two recognizers raced the *identical*
/// gesture (a bare hold with no movement, timed against the same
/// `kLongPressTimeout`), which the arena genuinely cannot break the tie on
/// and one had to be withheld by hand. A directional drag and a stationary
/// hold do not collide the same way - this is also, unmodified, the shape
/// the framework's own `Dismissible` uses to swipe an item out of a
/// vertically scrolling [ListView] with no extra plumbing at all.
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../desktop/desktop_window_shell.dart';
import '../desktop/window_resize_frame.dart';
import 'drawer_edge_swipe.dart';

/// How far a swipe must travel, in logical pixels, before releasing it
/// commits the reply - past this the reveal icon reads as armed rather than
/// merely present.
const double swipeToReplyThreshold = 64;

/// The reveal's own travel ceiling: a swipe carried well past the threshold
/// stops moving the row any further, so a long, fast swipe reads the same as
/// a short, deliberate one once either has committed.
const double _maxDrag = 96;

/// Wraps [child] so a touch-originated horizontal drag past
/// [swipeToReplyThreshold] calls [onCommit] on release.
///
/// Its own widget, reused per row rather than folded into [MessageRow]
/// itself, so a widget test can drive the gesture without the row's own
/// dozen other required fields - the same split [HoverReveal] already drew
/// for the same reason.
///
/// [enabled] mirrors [MessageActions.canReply] at every call site: a
/// message nobody may reply to (no `SEND_MESSAGES` in this channel, still
/// pending, already failed) swipes for nothing, the same "no handler at
/// all" treatment this codebase already gives an unavailable action
/// elsewhere (`AppSegmentedOption.disabled`, `ThreadReplySummary`'s own
/// inert-text branch) rather than a control that would only ever 403.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    super.key,
    required this.enabled,
    required this.onCommit,
    required this.child,
  });

  final bool enabled;

  /// Called once, on the release that crossed [swipeToReplyThreshold] - not
  /// on every frame past it, so a finger held past the threshold and dragged
  /// further does not stage several replies for one swipe.
  final VoidCallback onCommit;

  final Widget child;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  /// Tracks the row's own horizontal offset directly (its `.value` is set
  /// every frame while a finger is down, not animated) and is what animates
  /// the snap-back once the finger lifts - the same double duty
  /// `Dismissible`'s own `_moveController` already does for an identical
  /// reason: one controller for both a 1:1-tracked drag and its release
  /// animation, rather than a plain field for the first and a second
  /// controller layered on for the second.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    upperBound: _maxDrag,
  );

  /// Set from the [DragStartDetails] this drag actually began with, and read
  /// by every later callback in the same gesture - a pointer's device kind
  /// cannot change mid-drag, so one read at the start is enough. This is the
  /// whole gate that keeps a desktop mouse drag from moving the row at all:
  /// `_onUpdate` simply never runs the branch that would when this is false.
  bool _fromTouch = false;

  bool get _committed => _controller.value >= swipeToReplyThreshold;

  /// Where the finger actually landed, recorded from the raw pointer.
  ///
  /// [DragStartDetails.globalPosition] cannot answer this: with the default
  /// [DragStartBehavior.start] it reports where the drag was *recognised*,
  /// which is a touch-slop's travel (about 18px) inboard of the touch itself.
  /// Reading it instead put a touch at x=10 at roughly x=28, so a zone narrow
  /// enough to clear the row's avatar stopped catching the drags it exists to
  /// catch. Switching the recogniser to [DragStartBehavior.down] would fix the
  /// coordinate and cost the reveal its smooth start, since the first delta
  /// would then carry the whole slop.
  double? _downX;

  /// A drag beginning in the drawer's own edge zone is the drawer's, never a
  /// reply. Only where a drawer actually exists - at wider layouts the
  /// transcript does not start at the screen edge and there is nothing to open.
  bool get _startedInDrawerEdge {
    final x = _downX;
    if (x == null) return false;
    if (Scaffold.maybeOf(context)?.hasDrawer != true) return false;
    final left = DesktopWindowShell.frameless
        ? kWindowResizeHandleThickness
        : 0.0;
    return x >= left && x < left + kDrawerEdgeZoneWidth;
  }

  void _onStart(DragStartDetails details) {
    _fromTouch =
        details.kind == PointerDeviceKind.touch && !_startedInDrawerEdge;
  }

  /// Rubber-banded rather than free: clamped at 0 so a leftward flick never
  /// reads as an incomplete rightward one, and at the ceiling so an overshot
  /// or very fast swipe cannot move the row any further than a deliberate
  /// one already would have.
  void _onUpdate(DragUpdateDetails details) {
    if (!_fromTouch) return;
    _controller.value = (_controller.value + details.delta.dx).clamp(
      0.0,
      _maxDrag,
    );
  }

  void _onEnd(DragEndDetails details) {
    if (!_fromTouch) return;
    final committed = _committed;
    if (committed) {
      AppHaptics.impact();
      widget.onCommit();
    }
    _snapBack();
  }

  void _onCancel() {
    if (!_fromTouch) return;
    _snapBack();
  }

  /// An explicit `Duration.zero` (what [AppMotion.reduced] answers under
  /// reduce-motion) takes [AnimationController]'s own instant branch and
  /// sets the value synchronously rather than animating a single frame at
  /// 5% of some implicit duration - that scar is `animateTo`'s *inferred*
  /// duration only, verified by reading `animation_controller.dart` before
  /// relying on it here.
  void _snapBack() {
    _fromTouch = false;
    _controller.animateTo(
      0,
      duration: AppMotion.reduced(context, AppMotion.fast),
      curve: AppMotion.exit,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Listener(
      onPointerDown: (event) => _downX = event.position.dx,
      child: GestureDetector(
        onHorizontalDragStart: widget.enabled ? _onStart : null,
        onHorizontalDragUpdate: widget.enabled ? _onUpdate : null,
        onHorizontalDragEnd: widget.enabled ? _onEnd : null,
        onHorizontalDragCancel: widget.enabled ? _onCancel : null,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final dragX = _controller.value;
            final progress = (dragX / swipeToReplyThreshold).clamp(0.0, 1.0);
            return Stack(
              children: [
                if (dragX > 0)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.s16),
                        // Decorative: the reply banner appearing is the real, announced state change, not this icon.
                        child: ExcludeSemantics(
                          child: Opacity(
                            opacity: progress,
                            child: Icon(
                              AppIcons.reply,
                              size: 20,
                              color: _committed
                                  ? tokens.accent
                                  : tokens.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Transform.translate(offset: Offset(dragX, 0), child: child),
              ],
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}
