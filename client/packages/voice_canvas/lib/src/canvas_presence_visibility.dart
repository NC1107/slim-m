// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Which camera bubbles are worth mounting a live video widget for.
///
/// The Phase 5 spike found the canvas's real cliffs on viewport shape, not
/// object count (see the spike's own findings in the project knowledge
/// base): zooming out probes cost that scales with world area, not with how
/// much is actually drawn. A `VideoTrackRenderer` is a platform `Texture`,
/// not a paint call a cull can skip cheaply after the fact - so a bubble
/// mounted once must not be torn down and rebuilt every time a pan nudges it
/// a pixel past a single boundary, or a call sitting near the edge of the
/// screen churns its own video widgets every frame.
library;

import 'package:flutter/painting.dart';

/// A sticky viewport membership test: a bubble already mounted stays mounted
/// until it leaves the wider [exitMargin] band, and an unmounted bubble is
/// only mounted once it enters the narrower [enterMargin] band. Two
/// thresholds rather than one is what stops a bubble sitting exactly on a
/// single boundary from mounting and unmounting every recomputation.
class CanvasPresenceVisibility {
  CanvasPresenceVisibility({this.enterMargin = 200, this.exitMargin = 600})
      : assert(
          enterMargin <= exitMargin,
          'the exit band must not be tighter than the enter band, or a bubble '
          'could enter and immediately leave on the same recomputation',
        );

  /// How far outside the viewport a bubble may sit and still be mounted for
  /// the first time - kept a comfortable stroke inside [exitMargin] so its
  /// video texture is already loading before the bubble is fully on screen.
  final double enterMargin;

  /// How far outside the viewport an already-mounted bubble may drift before
  /// it is unmounted; wider than [enterMargin] on purpose, which is the whole
  /// mechanism this class exists for.
  final double exitMargin;

  Set<String> _mounted = const <String>{};

  /// Currently-mounted ids, as of the last [update].
  Set<String> get mounted => _mounted;

  /// Recomputes which of [bubbles] should be mounted, given the current
  /// [viewport]. An id absent from [bubbles] (a participant who left, or
  /// whose bubble was filtered out - blocked, say) is dropped unconditionally,
  /// even if it was mounted a moment ago.
  Set<String> update(Rect viewport, Map<String, Rect> bubbles) {
    final enterBand = viewport.inflate(enterMargin);
    final exitBand = viewport.inflate(exitMargin);
    final next = <String>{};
    bubbles.forEach((id, rect) {
      final band = _mounted.contains(id) ? exitBand : enterBand;
      if (band.overlaps(rect)) next.add(id);
    });
    _mounted = next;
    return next;
  }
}
