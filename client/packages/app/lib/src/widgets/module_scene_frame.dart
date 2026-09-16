// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The box a module's scene is drawn in, sized to the room it is given.
///
/// Two complaints shaped this, in opposite directions. A fixed 420px cap was
/// "a small square adrift" in a desktop card twice its width. Removing it for
/// a share of the window height then made a three-by-three board 650px tall
/// on a 1080p desktop, which the owner read as huge.
///
/// What reconciles them is that neither size is about the window: it is about
/// how big one cell has to be. A board is bounded by [maxCellSize] per cell,
/// so a tic-tac-toe grid stays a board rather than a billboard while a
/// forty-square life grid is still limited by the window as before. The
/// height share remains the outer bound, so no scene can push the transcript
/// off screen, and the width follows from the scene's own aspect ratio.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

class ModuleSceneFrame extends StatelessWidget {
  const ModuleSceneFrame({
    super.key,
    required this.aspect,
    required this.child,
    this.sceneHeight = 0,
  });

  /// Width over height of the scene's own coordinate space; anything at or
  /// below zero is treated as square.
  final double aspect;

  /// The scene's own height in its coordinate space, which for a cell grid
  /// is the row count. That is what decides whether a scene wants the room a
  /// big grid needs. Zero or less falls back to the window bound alone.
  final double sceneHeight;

  final Widget child;

  /// How much of the window a board may take before the width gives way.
  static const viewportShare = 0.6;

  /// The floor under that share, so a short window still gets a usable
  /// board rather than a sliver.
  static const minHeight = 240.0;

  /// The tallest one unit of the scene's own coordinate space may be drawn,
  /// which for a cell grid is one cell. Chosen so a three-row board lands
  /// near 480px: comfortably past the 420 that read as adrift, and well
  /// inside the 650 that read as huge. A grid with many rows is unaffected,
  /// because the window share binds long before this does.
  static const maxCellSize = 160.0;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final ratio = aspect <= 0 ? 1.0 : aspect;
    final windowBound = MediaQuery.sizeOf(context).height * viewportShare;
    final cellBound = sceneHeight > 0
        ? sceneHeight * maxCellSize
        : double.infinity;
    final maxHeight = math.max(minHeight, math.min(windowBound, cellBound));
    return LayoutBuilder(
      builder: (context, constraints) {
        final widthForHeight = maxHeight * ratio;
        final width = constraints.hasBoundedWidth
            ? math.min(constraints.maxWidth, widthForHeight)
            : widthForHeight;
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: width,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: tokens.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(aspectRatio: ratio, child: child),
            ),
          ),
        );
      },
    );
  }
}
