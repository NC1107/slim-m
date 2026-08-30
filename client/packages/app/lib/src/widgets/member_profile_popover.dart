// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The anchored placement half of the member profile popover, split out of
/// `member_profile.dart` to keep that file under the review budget.
library;

import 'package:flutter/material.dart';

/// Places [child] beside [origin]/[anchorSize], kept inside the viewport
/// rather than running off an edge - the same clamping the message context
/// menu does.
class AnchoredMemberPopover extends StatelessWidget {
  const AnchoredMemberPopover({
    super.key,
    required this.origin,
    required this.anchorSize,
    required this.width,
    required this.child,
  });

  final Offset origin;
  final Size anchorSize;

  /// The popover's own width on a pointer layout, from the design.
  final double width;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final view = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context) + const EdgeInsets.all(8);
    // Prefers the anchor's right side, flipping left when it would overhang.
    final left = (origin.dx + anchorSize.width + 8 + width > view.width)
        ? (origin.dx - width - 8).clamp(padding.left, view.width)
        : (origin.dx + anchorSize.width + 8).clamp(padding.left, view.width);
    final top = origin.dy.clamp(
      padding.top,
      (view.height - padding.bottom - 120).clamp(padding.top, view.height),
    );
    return Stack(
      children: [
        Positioned(
          left: left.toDouble(),
          top: top.toDouble(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: view.height - top - padding.bottom,
            ),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ],
    );
  }
}
