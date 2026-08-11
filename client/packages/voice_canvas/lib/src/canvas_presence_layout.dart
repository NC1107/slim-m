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

import 'dart:math' as math;

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
    this.maxRowWidth,
  });

  final double tileWidth;
  final double tileHeight;
  final double gap;

  /// Distance from the world origin to the first tile, so a fresh canvas's
  /// default camera (top-left at world `(0, 0)`) starts with bubbles already
  /// in view rather than off past the edge of the initial viewport.
  final double margin;

  /// How wide a row of tiles may grow before the next one wraps onto a new
  /// row, or null for the single unbounded row this class used to always
  /// build.
  ///
  /// A phone held upright is the case this exists for. Five tiles in one row
  /// span roughly 1220 world units, and a portrait pane is under 400 wide, so
  /// on the arrangement this class shipped with a phone could see exactly one
  /// bubble and had to pan sideways through empty world to reach the rest -
  /// along the axis portrait has least of. Wrapping spends the axis portrait
  /// actually has.
  ///
  /// The trade, stated rather than buried: this class's own promise that
  /// "every viewer computes the same answer" now holds only for viewers whose
  /// panes are the same width. That promise was always about the *fallback*
  /// for a tile nobody has touched - a drag, resize or lock lands in
  /// `CanvasPresenceTileOverrides` and is what actually persists - so what
  /// diverges is where an untouched bubble starts, never where a placed one
  /// stays. A default that puts a bubble somewhere a phone can never see it
  /// is the worse of the two.
  final double? maxRowWidth;

  /// This layout with [maxRowWidth] set to [width], or unbounded when [width]
  /// is not a usable one - `CanvasDocument.viewport` reads `Size.zero` for
  /// the frame before `CanvasSurface` has laid out and reported its real
  /// size, and a bound of zero would put every tile on its own row for that
  /// frame.
  CanvasPresenceLayout withMaxRowWidth(double width) => CanvasPresenceLayout(
        tileWidth: tileWidth,
        tileHeight: tileHeight,
        gap: gap,
        margin: margin,
        maxRowWidth: width > 0 ? width : null,
      );

  /// One world-space [Rect] per key, in rows ordered by sorted key - not join
  /// order, which is never the same string twice in a row across two clients
  /// that learned about a join at different times.
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
    final limit = maxRowWidth;
    var left = margin;
    var top = margin;
    var rowHeight = 0.0;
    for (final key in sorted) {
      final size = sizeFor?.call(key) ?? Size(tileWidth, tileHeight);
      // Never wrapped when it would open an empty row: a tile wider than the whole limit still has to land somewhere.
      if (limit != null && left > margin && left + size.width > limit) {
        left = margin;
        top += rowHeight + gap;
        rowHeight = 0;
      }
      placed[key] = Rect.fromLTWH(left, top, size.width, size.height);
      left += size.width + gap;
      rowHeight = math.max(rowHeight, size.height);
    }
    return placed;
  }
}
