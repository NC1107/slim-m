// SPDX-License-Identifier: Apache-2.0
/// A hand-rolled bar chart for the analytics screen's three small series.
///
/// No charting package: three simple bar charts do not carry the weight of a
/// new dependency (see `docs/dependencies.md`), and this project already
/// prefers a `CustomPainter` for exactly this kind of small, bespoke drawing
/// (the speaking ring, the status dot). This one widget is reused for all
/// three series - messages by day, active hours, and memory samples - rather
/// than growing a chart type per series.
///
/// Deliberately not the only representation of its data: a chart with no
/// accessible equivalent is a cue carried by one channel alone, which this
/// project's own accessibility stance treats as a failure everywhere else
/// (presence shape, the speaking glyph). [semanticsLabel] carries the full
/// series as text for assistive tech, and the caller is expected to print
/// the headline numbers (a total, a peak) as ordinary visible text alongside
/// the chart - see `analytics_screen.dart` for where that happens.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

class AnalyticsBarChart extends StatelessWidget {
  const AnalyticsBarChart({
    super.key,
    required this.values,
    required this.semanticsLabel,
    this.height = 96,
  });

  final List<double> values;
  final String semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) => CustomPaint(
            size: Size(constraints.maxWidth, height),
            painter: _BarsPainter(
              values: values,
              barColor: tokens.accentFill,
              baselineColor: tokens.borderSubtle,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.barColor,
    required this.baselineColor,
  });

  final List<double> values;
  final Color barColor;
  final Color baselineColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = baselineColor
        ..strokeWidth = 1,
    );
    if (values.isEmpty || size.width <= 0) return;

    final maxValue = values.fold<double>(0, (m, v) => v > m ? v : m);
    final barWidth = size.width / values.length;
    final gap = barWidth * 0.2;
    final paint = Paint()..color = barColor;
    for (var i = 0; i < values.length; i++) {
      if (maxValue <= 0) break;
      final barHeight = (values[i] / maxValue) * (size.height - 2);
      if (barHeight <= 0) continue;
      canvas.drawRect(
        Rect.fromLTWH(
          i * barWidth + gap / 2,
          size.height - barHeight,
          barWidth - gap,
          barHeight,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.barColor != barColor;
}
