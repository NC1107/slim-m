// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The box a module's scene is drawn in, sized to the room it is given.
///
/// This used to be a fixed 420px cap, which on a phone was the whole width
/// and on a desktop transcript a small square adrift in a card twice its
/// size - the owner read it as the scene not scaling. The board now fills
/// whatever width the card offers, bounded only so a tall scene can never
/// push the rest of the transcript off screen: its height stops at a share
/// of the window, and the width follows from the scene's own aspect ratio.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

class ModuleSceneFrame extends StatelessWidget {
  const ModuleSceneFrame({
    super.key,
    required this.aspect,
    required this.child,
  });

  /// Width over height of the scene's own coordinate space; anything at or
  /// below zero is treated as square.
  final double aspect;
  final Widget child;

  /// How much of the window a board may take before the width gives way.
  static const viewportShare = 0.6;

  /// The floor under that share, so a short window still gets a usable
  /// board rather than a sliver.
  static const minHeight = 240.0;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final ratio = aspect <= 0 ? 1.0 : aspect;
    final maxHeight = math.max(
      minHeight,
      MediaQuery.sizeOf(context).height * viewportShare,
    );
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
