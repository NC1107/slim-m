// SPDX-License-Identifier: Apache-2.0
/// Where the transcript's scroll sits, and the two things that follow from
/// it: the "jump to latest" affordance's visibility and when a viewed
/// message is marked read.
///
/// Split out of `channel_screen.dart`, which had no line budget left to grow
/// into. It owns the [ScrollController] itself, not just state derived from
/// it, because both have to survive `ChannelScreen`'s own outlives-a-channel-
/// switch lifetime (see `channel_read_marker.dart`'s doc comment) and reset
/// together: a controller reset with nothing telling the arrow to hide, or
/// an arrow hidden while the controller still sits mid-history, are each
/// half of the same bug on their own.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:slimm_design_system/design_system.dart';

class TranscriptScrollTracker {
  TranscriptScrollTracker({required this.markRead}) {
    controller.addListener(_onScrollChanged);
  }

  /// Called with the channel's newest delivered seq and last-read marker
  /// once the transcript is confirmed at the latest message.
  final void Function(int seq, int lastReadSeq) markRead;

  final ScrollController controller = ScrollController();

  /// A [ValueNotifier] rather than a `setState`-tracked field on purpose:
  /// rebuilding the whole screen on every scroll frame that crosses a
  /// threshold would make the read marker's own correctness depend on that
  /// rebuild reaching the transcript's gate, which [_onScrollChanged] is not
  /// allowed to lean on.
  final ValueNotifier<bool> scrolledAway = ValueNotifier(false);

  bool _disposed = false;
  int _latestSeq = 0;
  int _lastReadSeq = 0;

  /// How close to [ScrollPosition.minScrollExtent] still counts as "at the
  /// latest message" for read-marking, covering overscroll bounce and float
  /// rounding from [scrollToLatest]'s own animation landing. Deliberately
  /// tight and unrelated to [_scrolledAwayFraction]: marking read is about
  /// truly being back at the bottom, not about the arrow's own, coarser,
  /// "did the reader mean to leave" question below.
  static const double _atLatestSlop = 4;

  /// How much of the viewport must be scrolled past the newest message
  /// before the jump-to-latest control shows. Screen-relative rather than a
  /// fixed pixel count, since the same absolute distance is a full screen on
  /// a phone and a sliver of a wide desktop window: 30% of whatever is
  /// currently visible is "no longer looking at the tail of the
  /// conversation" on either.
  static const double _scrolledAwayFraction = 0.3;

  /// Floor under [_scrolledAwayFraction], roughly two grouped message rows,
  /// so a short viewport (a compact split-pane column) still asks for a real
  /// scroll rather than a few dozen pixels of one.
  static const double _scrolledAwayFloor = 96;

  void dispose() {
    _disposed = true;
    controller
      ..removeListener(_onScrollChanged)
      ..dispose();
    scrolledAway.dispose();
  }

  /// True while the viewport shows the newest message: no scrollable has
  /// attached yet (nothing has laid out to have scrolled away from, and the
  /// list starts bottom-anchored so a first paint always begins there), or
  /// the offset already sits within [_atLatestSlop] of
  /// [ScrollPosition.minScrollExtent].
  bool get atLatest {
    if (!controller.hasClients) return true;
    final position = controller.position;
    return position.pixels <= position.minScrollExtent + _atLatestSlop;
  }

  bool get _scrolledAwayEnough {
    if (!controller.hasClients) return false;
    final position = controller.position;
    final threshold = math.max(
      position.viewportDimension * _scrolledAwayFraction,
      _scrolledAwayFloor,
    );
    return position.pixels - position.minScrollExtent > threshold;
  }

  /// Scrolling never rebuilds the transcript's `StreamBuilder`, so returning
  /// to the latest message needs its own trigger to re-mark read; this is
  /// it, on its own, independent of whether the arrow happens to repaint.
  void _onScrollChanged() {
    final wasAtLatest = atLatest;
    scrolledAway.value = _scrolledAwayEnough;
    if (wasAtLatest) markRead(_latestSeq, _lastReadSeq);
  }

  /// Called on every transcript rebuild, so a scroll event arriving between
  /// rebuilds always marks read against the channel actually on screen.
  void updateKnownSeqs({required int latestSeq, required int lastReadSeq}) {
    _latestSeq = latestSeq;
    _lastReadSeq = lastReadSeq;
  }

  /// A new channel always opens at its own newest message: without this, a
  /// channel opened right after scrolling into a different one's history
  /// opened already scrolled away from its own newest message too, since the
  /// controller and [scrolledAway] both outlive the switch.
  ///
  /// The jump itself is deferred a frame so it lands after the transcript
  /// has rebuilt for the new channel: doing it inline would fire
  /// [_onScrollChanged] against [_latestSeq] and [_lastReadSeq], which still
  /// hold the previous channel's values at the point a channel switch is
  /// noticed.
  void resetForChannelSwitch() {
    scrolledAway.value = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !controller.hasClients) return;
      controller.jumpTo(controller.position.minScrollExtent);
    });
  }

  /// The list is reversed, so the latest message sits at offset zero.
  void scrollToLatest({required Duration duration}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !controller.hasClients) return;
      controller.animateTo(
        controller.position.minScrollExtent,
        duration: duration,
        curve: AppMotion.entrance,
      );
    });
  }
}
