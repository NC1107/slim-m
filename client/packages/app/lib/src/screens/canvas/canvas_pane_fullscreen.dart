// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
part of 'canvas_pane.dart';

/// Entering and leaving fullscreen, and the tool swap that rides with it.
///
/// A `part of` rather than plain methods for the same reason
/// `_CanvasPaneHelpers` and `_CanvasPaneGestures` already are:
/// `canvas_pane.dart` has no room under the file budget, and this needs
/// `_CanvasPaneState`'s own fields. `setState` and `mounted` are `@protected`
/// on `State`, so nothing here calls either directly - `_refresh` is the
/// bridge that already exists for exactly that.
extension _CanvasPaneFullscreen on _CanvasPaneState {
  bool get _fullscreen =>
      ref.watch(canvasFullscreenProvider) == widget.channelId;

  /// Flips fullscreen for this channel, disarming the pen on the way in and
  /// putting the previous tool back on the way out.
  ///
  /// The tool swap is what makes a viewing mode safe to offer at all: with
  /// the tool strip folded away, a one-finger drag would otherwise still draw
  /// with whatever was armed, because `CanvasSurface` pans and zooms on two
  /// pointers only. [CanvasTool.select] places nothing, and on empty space it
  /// selects nothing either, so a drag through open canvas does what a person
  /// entering a "just show me the content" mode expects it to.
  void _toggleFullscreen() {
    final notifier = ref.read(canvasFullscreenProvider.notifier);
    if (_fullscreen) {
      notifier.state = null;
      // Whatever was armed on the way in, or the pen if this pane opened straight into fullscreen and has nothing of its own to restore.
      _refresh(() => _tool = _toolBeforeFullscreen ?? CanvasTool.pen);
      _toolBeforeFullscreen = null;
      return;
    }
    notifier.state = widget.channelId;
    _refresh(() {
      _toolBeforeFullscreen = _tool;
      _tool = CanvasTool.select;
    });
  }

  /// Closes the canvas outright. Clears fullscreen in the same motion, or a
  /// channel reopened later would come back with its chrome already dropped
  /// and no memory of why.
  void _closeCanvas() {
    ref.read(canvasFullscreenProvider.notifier).state = null;
    ref.read(canvasOpenProvider.notifier).state = null;
  }
}
