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

/// Deterministic placement for camera bubbles, purely a function of who is
/// present. No drag, no persistence, no per-client state: a bubble's
/// position is recomputed fresh from the current roster every time, which is
/// what "reset on rejoin" (STRATEGY's own phrase for presence objects) means
/// taken literally - there is nothing to reset because nothing is kept.
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

  /// One world-space [Rect] per identity, in a single row ordered by sorted
  /// identity - not join order, which is never the same string twice in a
  /// row across two clients that learned about a join at different times.
  Map<String, Rect> arrange(Iterable<String> identities) {
    final sorted = identities.toList()..sort();
    final placed = <String, Rect>{};
    for (var i = 0; i < sorted.length; i++) {
      final left = margin + i * (tileWidth + gap);
      placed[sorted[i]] = Rect.fromLTWH(left, margin, tileWidth, tileHeight);
    }
    return placed;
  }
}
