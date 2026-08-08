// SPDX-License-Identifier: Apache-2.0
/// Where a call participant's camera bubble sits in world space.
///
/// A camera bubble is ephemeral presence, never a persisted object (see
/// `docs/STRATEGY.md`'s "presence versus content" split), so there is no
/// `x`/`y` on the wire to place it from - unlike a pasted image, which
/// carries its own coordinates. [CanvasPresenceLayout] answers the same
/// question every client asks independently: given who is on the call right
/// now, where does each of them sit. Sorting the identity set is what makes
/// every viewer compute the same answer with nothing sent over the wire.
library;

import 'package:flutter/painting.dart';

/// Deterministic placement for camera and screen-share tiles, purely a
/// function of who is present. It is the *fallback* a tile starts at, not
/// the whole story any more: `CanvasPresenceTileOverrides` is where a drag,
/// a resize, a lock or a hide actually lives now, one viewer at a time (see
/// its own doc for why that is personal rather than shared). This class
/// still has no drag and no persistence of its own - a tile with no override
/// on record is recomputed fresh from the current roster every time, which
/// is what "reset on rejoin" (STRATEGY's own phrase for presence objects)
/// means taken literally for the tiles nobody has ever touched.
class CanvasPresenceLayout {
  const CanvasPresenceLayout({
    this.tileWidth = 220,
    this.tileHeight = 160,
    this.gap = 24,
    this.margin = 24,
  });

  final double tileWidth;
  final double tileHeight;
  final double gap;

  /// Distance from the world origin to the first tile, so a fresh canvas's
  /// default camera (top-left at world `(0, 0)`) starts with bubbles already
  /// in view rather than off past the edge of the initial viewport.
  final double margin;

  /// One world-space [Rect] per key, in a single row ordered by sorted
  /// key - not join order, which is never the same string twice in a row
  /// across two clients that learned about a join at different times.
  ///
  /// [sizeFor], when given, answers each key's own tile size (a screen
  /// share is wider than a camera tile); left null every key gets
  /// [tileWidth]/[tileHeight], [arrange]'s original uniform behaviour.
  Map<String, Rect> arrange(
    Iterable<String> identities, {
    Size Function(String key)? sizeFor,
  }) {
    final sorted = identities.toList()..sort();
    final placed = <String, Rect>{};
    var left = margin;
    for (final key in sorted) {
      final size = sizeFor?.call(key) ?? Size(tileWidth, tileHeight);
      placed[key] = Rect.fromLTWH(left, margin, size.width, size.height);
      left += size.width + gap;
    }
    return placed;
  }
}
