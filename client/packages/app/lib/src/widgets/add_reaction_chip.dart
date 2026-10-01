// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The dashed "+" that ends a message's reaction chips: an invitation to add
/// another, drawn as an outline of the thing it would become.
library;

import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// Matches [AppChip.reaction]'s own height so the two share a line.
const double _chipHeight = 24;

/// Dash and gap in dp: geometry of the outline, not a token.
const double _dash = 3;

class AddReactionChip extends StatelessWidget {
  const AddReactionChip({super.key, required this.onTap});

  /// The drawn outline, without the focus ring's margin around it.
  static const bodyKey = Key('reactions_add_chip_body');

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Tooltip(
      message: 'Add reaction',
      excludeFromSemantics: true,
      child: FocusableTapTarget(
        onTap: onTap,
        semanticLabel: 'Add reaction',
        ringRadius: AppRadii.full,
        builder: (context, focused, hovered) => CustomPaint(
          painter: _DashedPillPainter(
            color: hovered ? tokens.borderStrong : tokens.borderSubtle,
          ),
          child: SizedBox(
            key: bodyKey,
            height: _chipHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
              child: Icon(
                AppIcons.add,
                size: AppSizes.icon16,
                color: hovered ? tokens.textPrimary : tokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedPillPainter extends CustomPainter {
  const _DashedPillPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          Radius.circular(size.height / 2),
        ),
      );
    for (final PathMetric metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += _dash * 2) {
        canvas.drawPath(metric.extractPath(at, at + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPillPainter old) => old.color != color;
}
