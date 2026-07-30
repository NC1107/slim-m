// SPDX-License-Identifier: Apache-2.0
/// The one place a drawn size becomes a decode cap, so every image site
/// picks it the same way rather than reimplementing the multiply-and-round.
library;

import 'package:flutter/widgets.dart';

/// The `cacheWidth`/`cacheHeight` (or [ResizeImage] `width`/`height`) an
/// image drawn at [logicalSize] should decode to.
///
/// Those parameters are real pixels, not logical ones: without multiplying by
/// [MediaQuery.devicePixelRatioOf], a high-DPI screen would decode at fewer
/// pixels than it paints, which is exactly the softness this exists to avoid
/// while still bounding memory.
int decodeEdge(BuildContext context, double logicalSize) =>
    (logicalSize * MediaQuery.devicePixelRatioOf(context)).round();
