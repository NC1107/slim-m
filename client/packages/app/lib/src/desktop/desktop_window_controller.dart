// SPDX-License-Identifier: Apache-2.0
/// Reacts to the window's own lifecycle: persists geometry on a settled
/// resize or move, and routes a close through [resolveCloseAction] rather
/// than letting the OS quit the process. One controller rather than two,
/// per decision 0012's framing - "one shape rather than three features".
library;

import 'dart:async';

import 'close_behavior.dart';
import 'desktop_window_port.dart';
import 'window_geometry.dart';
import 'window_geometry_store.dart';

/// How long to wait after the last resize/move event before writing, on the
/// assumption the drag has ended.
///
/// Only load-bearing on Linux: `window_manager`'s own `WindowListener` doc
/// comment marks `onWindowResized`/`onWindowMoved` (the settled variants)
/// `@platforms macos,windows` only, confirmed by reading the Linux plugin's
/// native source - it emits only the continuous `resize`/`move` events,
/// mapped from GTK's `check-resize` and `configure-event`, both of which
/// fire repeatedly across one drag. So on Linux this debounce is the only
/// thing standing in for a settled event the platform never reports.
const desktopGeometryDebounce = Duration(milliseconds: 500);

class DesktopWindowController {
  DesktopWindowController({
    required this.port,
    required this.store,
    required this.platform,
    required this.trayAvailable,
    this.onShow,
    this.debounce = desktopGeometryDebounce,
  });

  final DesktopWindowPort port;
  final WindowGeometryStore store;
  final DesktopPlatform platform;

  /// Queried live on every close, never cached - a tray host can appear or
  /// disappear mid-session, and a stale cached answer would be wrong in
  /// either direction. See decision 0012's own reasoning for why this is
  /// not a startup-time check.
  final Future<bool> Function() trayAvailable;

  /// Fired once per window-show, so a caller can offer the first-time-only
  /// tray notice at the one moment the window is back on screen to show it.
  final void Function()? onShow;

  final Duration debounce;

  Timer? _debounceTimer;
  StreamSubscription<DesktopWindowEventKind>? _subscription;

  void start() {
    _subscription = port.events.listen(_onEvent);
  }

  void dispose() {
    _debounceTimer?.cancel();
    _subscription?.cancel();
  }

  Future<void> _onEvent(DesktopWindowEventKind kind) async {
    switch (kind) {
      case DesktopWindowEventKind.resize:
      case DesktopWindowEventKind.move:
        _scheduleWrite();
      case DesktopWindowEventKind.maximize:
      case DesktopWindowEventKind.unmaximize:
      case DesktopWindowEventKind.fullScreen:
      case DesktopWindowEventKind.leaveFullScreen:
        await _writeNow();
      case DesktopWindowEventKind.close:
        await requestClose();
      case DesktopWindowEventKind.show:
        onShow?.call();
    }
  }

  /// The one place "close" is actually carried out, reached both from the
  /// native close/delete-event and from the custom title bar's own close
  /// button once the native one no longer exists to trigger that event at
  /// all - a title-bar button that only called [DesktopWindowPort.hide]
  /// directly would skip the tray-availability fallback entirely, hiding
  /// the window with nothing to bring it back on a Linux desktop with no
  /// tray host registered.
  Future<void> requestClose() async {
    await _writeNow();
    await _routeClose();
  }

  void _scheduleWrite() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, _writeNow);
  }

  Future<void> _writeNow() async {
    _debounceTimer?.cancel();
    await store.write(await _currentGeometry());
  }

  /// While maximized or fullscreen, [DesktopWindowPort.getBounds] answers
  /// with the maximized/fullscreen rectangle, not the windowed one - writing
  /// that as [WindowGeometry.windowedSize] would overwrite the very value a
  /// later "return to windowed" needs, so only [WindowRunState] moves and the
  /// previously stored windowed size and position are kept untouched.
  Future<WindowGeometry> _currentGeometry() async {
    final previous = store.read() ?? WindowGeometry.fallback;
    final maximized = await port.isMaximized();
    final fullscreen = await port.isFullScreen();
    if (maximized || fullscreen) {
      return previous.copyWith(
        runState: fullscreen
            ? WindowRunState.fullscreen
            : WindowRunState.maximized,
      );
    }
    final bounds = await port.getBounds();
    return WindowGeometry(
      windowedSize: WindowSize(width: bounds.width, height: bounds.height),
      position: bounds,
      runState: WindowRunState.windowed,
    );
  }

  Future<void> _routeClose() async {
    final action = resolveCloseAction(
      platform: platform,
      trayAvailable: await trayAvailable(),
    );
    switch (action) {
      case CloseAction.hideToTray:
        await port.hide();
      case CloseAction.minimizeToTaskbar:
        await port.minimize();
    }
  }
}
