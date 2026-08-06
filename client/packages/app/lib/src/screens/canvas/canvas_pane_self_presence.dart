// SPDX-License-Identifier: Apache-2.0
part of 'canvas_pane.dart';

/// The caller's own camera bubble's two callbacks: split out of
/// `_CanvasPaneState` once wiring them pushed `canvas_pane.dart` past the
/// 500-line hard limit, the same reason `canvas_pane_gestures.dart`'s own
/// doc names.
extension _CanvasPaneSelfPresence on _CanvasPaneState {
  void _onSelfBubbleCornerChanged(CanvasSelfBubbleCorner corner) => unawaited(
    ref.read(canvasSelfPresenceProvider.notifier).setCorner(corner),
  );

  /// Reads the current value fresh rather than closing over whatever
  /// `build()` last saw, so two fast taps land as a toggle rather than both
  /// racing to set the identical value.
  void _onToggleSelfBubbleHidden() => unawaited(
    ref
        .read(canvasSelfPresenceProvider.notifier)
        .setHidden(!ref.read(canvasSelfPresenceProvider).hidden),
  );
}
