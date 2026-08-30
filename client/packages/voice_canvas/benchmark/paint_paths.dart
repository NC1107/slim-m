// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The two ways a canvas frame can reach the paint layer, reduced to the
/// smallest tree that still tells them apart.
///
/// Shared by the hot-path benchmark and the regression test that keeps the
/// render loop off Riverpod. The painters draw nothing on purpose: this spike
/// measures the pipeline, not rasterisation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

class PaintStats {
  int builds = 0;
  int paints = 0;

  void reset() {
    builds = 0;
    paints = 0;
  }
}

/// The bet: the scene is the painter's `repaint` listenable, so a viewport
/// change marks the render object dirty without touching the element tree.
class RepaintOnlyCanvas extends StatefulWidget {
  const RepaintOnlyCanvas(
      {required this.scene, required this.stats, super.key});

  final CanvasScene scene;
  final PaintStats stats;

  @override
  State<RepaintOnlyCanvas> createState() => _RepaintOnlyCanvasState();
}

class _RepaintOnlyCanvasState extends State<RepaintOnlyCanvas> {
  late final _ScenePainter _painter = _ScenePainter(
    widget.scene,
    widget.stats,
  );

  @override
  Widget build(BuildContext context) {
    widget.stats.builds++;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        child: CustomPaint(size: const Size(400, 300), painter: _painter),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.stats) : super(repaint: scene);

  final CanvasScene scene;
  final PaintStats stats;

  @override
  void paint(Canvas canvas, Size size) {
    stats.paints++;
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) => false;
}

/// The naive alternative: the viewport lives in a provider, so every frame
/// rebuilds a widget and reconciles an element before anything can paint.
class RebuildCanvas extends ConsumerWidget {
  const RebuildCanvas({
    required this.counter,
    required this.stats,
    super.key,
  });

  final StateProvider<int> counter;
  final PaintStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    stats.builds++;
    final value = ref.watch(counter);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size(400, 300),
          painter: _ValuePainter(value, stats),
        ),
      ),
    );
  }
}

class _ValuePainter extends CustomPainter {
  _ValuePainter(this.value, this.stats);

  final int value;
  final PaintStats stats;

  @override
  void paint(Canvas canvas, Size size) {
    stats.paints++;
  }

  @override
  bool shouldRepaint(_ValuePainter oldDelegate) => oldDelegate.value != value;
}
