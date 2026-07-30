// SPDX-License-Identifier: Apache-2.0
/// Where an open message context menu lands, split out of
/// `message_context_menu.dart` to keep that file inside the review budget.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Places the menu at its anchor, sliding it back inside the viewport rather
/// than letting it run off an edge: a long-press on a message low on a phone
/// screen otherwise puts Delete past the bottom of the display.
class MessageMenuLayout extends SingleChildLayoutDelegate {
  const MessageMenuLayout({required this.anchor, required this.padding});

  final Offset anchor;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(padding);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = size.width - padding.right - childSize.width;
    final maxY = size.height - padding.bottom - childSize.height;
    return Offset(
      anchor.dx.clamp(padding.left, math.max(padding.left, maxX)),
      anchor.dy.clamp(padding.top, math.max(padding.top, maxY)),
    );
  }

  @override
  bool shouldRelayout(MessageMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor || padding != oldDelegate.padding;
}
