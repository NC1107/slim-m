// SPDX-License-Identifier: Apache-2.0
/// The background lattice, as its own standalone widget rather than one
/// more layer inside `CanvasSurface`'s own paint stack.
///
/// Split out so a caller can mount it *before* a non-interactive backdrop
/// layer of its own (a sent-to-back presence tile's video, in the app
/// layer's `CanvasPresenceBackdrop`) while `CanvasSurface` - grid included,
/// until this split - still paints everything above it. Before this, the
/// grid was the bottom layer of `CanvasSurface`'s own internal stack, which
/// put it *above* anything mounted behind the whole surface: a sent-to-back
/// tile's video composited under real ink correctly, but the grid lines
/// still drew over it, the one layer that never got the memo.
///
/// Deliberately not interactive: unlike `CanvasSurface`, which wraps its
/// whole paint stack in an opaque `MouseRegion` and `Listener` for panning
/// and drawing, this widget carries no gesture or pointer handling of its
/// own, so mounting it anywhere in a `Stack` costs nothing beyond the paint
/// itself and never competes for a hit test.
library;

import 'package:flutter/widgets.dart';

import 'canvas_document.dart';
import 'canvas_painters.dart';

/// The grid alone, sized to fill whatever space its parent gives it.
class CanvasGridLayer extends StatelessWidget {
  const CanvasGridLayer(
      {super.key, required this.document, required this.line});

  final CanvasDocument document;
  final Color line;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child:
            CustomPaint(painter: GridPainter(document: document, line: line)),
      );
}
