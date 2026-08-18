// SPDX-License-Identifier: Apache-2.0
/// The one place a drawn size becomes a decode cap, so every image site
/// picks it the same way rather than reimplementing the multiply-and-round.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The `cacheWidth`/`cacheHeight` (or [ResizeImage] `width`/`height`) an
/// image drawn at [logicalSize] should decode to.
///
/// Those parameters are real pixels, not logical ones: without multiplying by
/// [MediaQuery.devicePixelRatioOf], a high-DPI screen would decode at fewer
/// pixels than it paints, which is exactly the softness this exists to avoid
/// while still bounding memory.
///
/// [minRatio] floors that multiplier. It exists because a desktop compositor
/// can scale the window without the scale reaching Flutter as a device pixel
/// ratio - the well-known Linux fractional-scaling case, where the view
/// reports 1.0 while the surface is drawn larger - which starves a decode
/// sized on the reported ratio and shows as a soft, pixelated image. A small
/// image with a large source (an avatar re-encoded to 512) can afford to
/// decode past its reported need to stay crisp when that happens; a large
/// image cannot, so the floor is opt-in per call site rather than global.
int decodeEdge(
  BuildContext context,
  double logicalSize, {
  double minRatio = 1,
}) {
  final ratio = math.max(MediaQuery.devicePixelRatioOf(context), minRatio);
  return (logicalSize * ratio).round();
}
