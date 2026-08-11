// SPDX-License-Identifier: Apache-2.0
/// Ties every other file in this directory into the two calls `main.dart`
/// actually makes: apply saved geometry before the window is ever shown, and
/// wire up close-to-tray, geometry persistence and the tray icon once the
/// app has a [ProviderContainer] to read the running call's state from.
///
/// A no-op on every platform but Linux, macOS and Windows: `main.dart` calls
/// both methods unconditionally, and each returns immediately off
/// [currentDesktopPlatform] being null rather than making every call site
/// guard itself.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/providers.dart';
import 'close_behavior.dart';
import 'desktop_window_controller.dart';
import 'desktop_window_port.dart';
import 'first_run_tray_notice.dart';
import 'tray/desktop_tray_controller.dart';
import 'tray/linux_tray_probe.dart';
import 'tray/tray_availability.dart';
import 'window_geometry.dart';
import 'window_geometry_store.dart';

class DesktopWindowShell {
  DesktopWindowShell._();

  /// Shared across [applyInitialGeometry] and [registerListenersAndTray]:
  /// the native listener must be registered exactly once, which is what
  /// [WindowManagerDesktopWindowPort.ensureInitialized]'s own idempotence
  /// guards, and both steps need the one real window either way.
  static final DesktopWindowPort _port = WindowManagerDesktopWindowPort();

  static DesktopWindowController? _controller;
  static DesktopTrayController? _trayController;
  static bool _active = false;
  static bool _framelessApplied = false;

  /// The one port [TitleBar] drags, minimizes and maximizes through.
  static DesktopWindowPort get port => _port;

  /// True once [registerListenersAndTray] has actually run against a real
  /// desktop platform - never true in an ordinary widget test, since
  /// nothing in a `flutter test` run ever calls it. [DesktopChrome] reads
  /// this, not [isDesktopHost], specifically so a test run on this
  /// project's own Linux dev box or CI runner - which really is Linux, as
  /// far as `dart:io`'s `Platform` can tell - does not silently wrap every
  /// existing widget test's tree in a `Column` it never had before.
  static bool get active => _active;

  /// True only once the native frame has actually been hidden - by
  /// construction, always true by the time the ready app's chrome ever
  /// builds, since [registerListenersAndTray] is itself part of the same
  /// awaited bootstrap sequence gating that first build.
  static bool get frameless => _framelessApplied;

  /// The close button drawn inside [TitleBar] has no native close event of
  /// its own to reach [DesktopWindowController.requestClose] through, so it
  /// calls this instead - a no-op if the shell was never started, which
  /// cannot happen once [frameless] is true.
  static Future<void> requestClose() =>
      _controller?.requestClose() ?? Future<void>.value();

  /// Applies the saved size, position and run state before the window is
  /// ever shown, so there is nothing to visibly jump once it appears -
  /// `main.dart` calls this before `runApp`, ahead of the startup screen's
  /// own first frame.
  static Future<void> applyInitialGeometry() async {
    if (currentDesktopPlatform() == null) return;
    await _port.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final saved = WindowGeometryStore(prefs).read() ?? WindowGeometry.fallback;
    final geometry = clampToAttachedDisplays(saved, await _port.allDisplays());

    final position = geometry.position;
    if (position != null) {
      await _port.setBounds(
        WindowRect(
          x: position.x,
          y: position.y,
          width: geometry.windowedSize.width,
          height: geometry.windowedSize.height,
        ),
      );
    } else {
      await _port.setSize(geometry.windowedSize);
      await _port.center();
    }

    switch (geometry.runState) {
      case WindowRunState.maximized:
        await _port.maximize();
      case WindowRunState.fullscreen:
        await _port.setFullScreen(true);
      case WindowRunState.windowed:
        break;
    }
  }

  /// Wires geometry persistence, close-to-tray/minimise, and the tray icon
  /// itself - everything that needs [container] to reach a running call's
  /// state, so it runs after the container exists rather than before
  /// `runApp` the way [applyInitialGeometry] does.
  static Future<void> registerListenersAndTray(
    ProviderContainer container,
  ) async {
    final platform = currentDesktopPlatform();
    if (platform == null) return;
    _active = true;
    await _port.ensureInitialized();

    final prefs = await container.read(preferencesProvider.future);
    final store = WindowGeometryStore(prefs);
    final trayAvailable = trayAvailabilityCheck(
      platform: platform,
      probe: const MethodChannelLinuxTrayProbe(),
    );

    _controller = DesktopWindowController(
      port: _port,
      store: store,
      platform: platform,
      trayAvailable: trayAvailable,
      onShow: () => _offerFirstRunNoticeIfNeeded(container),
    )..start();

    await _port.setPreventClose(true);
    // Linux ships the frameless bar first; see decision 0012.
    if (platform == DesktopPlatform.linux) {
      await _port.hideTitleBar();
      _framelessApplied = true;
    }

    _trayController = DesktopTrayController(port: _port, container: container);
    await _trayController!.start();
  }

  static Future<void> _offerFirstRunNoticeIfNeeded(
    ProviderContainer container,
  ) async {
    final notice = await container.read(firstRunTrayNoticeProvider.future);
    if (notice.hasBeenShown) return;
    container.read(firstRunTrayNoticeVisibleProvider.notifier).state = true;
  }
}
