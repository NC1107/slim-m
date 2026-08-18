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

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/debug_log.dart';
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
  /// guards, and both steps need the one real window either way. Not
  /// `final`: [debugPort] is the test-only seam that swaps it for a fake.
  static DesktopWindowPort _port = WindowManagerDesktopWindowPort();

  /// How long [registerListenersAndTray] waits on the native window/tray
  /// calls before giving up and letting startup proceed regardless - a
  /// hang here (a D-Bus call with nothing answering it, say) would
  /// otherwise never resolve, which is the same silent-forever startup
  /// screen a thrown exception used to cause before this file caught one.
  static const _setupTimeout = Duration(seconds: 5);

  /// Named to match `linux_second_instance_channel.cc`, the only sender.
  static const _secondInstanceChannelName =
      'top.npcserver.slimm/linux_second_instance';

  static DesktopWindowController? _controller;
  static DesktopTrayController? _trayController;
  static bool _active = false;
  static bool _framelessApplied = false;

  /// Test-only seam: a real desktop-shell test still runs on real Linux
  /// (`dart:io`'s `Platform` cannot tell a CI runner from a launch), so
  /// this is what lets a test drive [registerListenersAndTray] against a
  /// fake port rather than the real plugin.
  @visibleForTesting
  static set debugPort(DesktopWindowPort port) => _port = port;

  /// Restores every static field to its never-started state, for a test
  /// that wants a clean slate rather than whatever an earlier test in the
  /// same file left behind.
  @visibleForTesting
  static void debugReset() {
    _port = WindowManagerDesktopWindowPort();
    _controller = null;
    _trayController = null;
    _active = false;
    _framelessApplied = false;
  }

  /// Flips the two flags [DesktopChrome] reads, so a widget test can render
  /// the active chrome without driving the whole native bring-up. Pair with
  /// [debugPort] and [debugReset]; [frameless] mounts the title bar.
  @visibleForTesting
  static void debugActivate({bool frameless = false}) {
    _active = true;
    _framelessApplied = frameless;
  }

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

  /// Registers the Linux-only receiving end of
  /// `linux_second_instance_channel.cc`'s notification that a launcher
  /// click re-entered the native `activate` handler in this process rather
  /// than starting a second one. `main.dart` calls this right after
  /// [applyInitialGeometry], before there is a [ProviderContainer], since a
  /// second launch racing the very start of this process is not something
  /// any later ordering could rule out.
  static void registerSecondInstanceHandler() {
    if (currentDesktopPlatform() == null) return;
    const MethodChannel(
      _secondInstanceChannelName,
    ).setMethodCallHandler(_onSecondInstanceCall);
  }

  /// show() is the same call [DesktopTrayController]'s own toggle makes to
  /// un-hide a tray-hidden window; restore() additionally raises one that
  /// was only minimised or merely behind other windows - both reuse the
  /// port's existing methods rather than a second "make it visible" path.
  /// Best-effort: the process-level dedup this exists for already happened
  /// natively, in `my_application.cc`'s own early return, before this ran.
  static Future<void> _onSecondInstanceCall(MethodCall call) async {
    if (call.method != 'focus') return;
    try {
      await _port.show();
      await _port.restore();
    } catch (_) {}
  }

  /// Wires geometry persistence, close-to-tray/minimise, and the tray icon
  /// itself - everything that needs [container] to reach a running call's
  /// state, so it runs after the container exists rather than before
  /// `runApp` the way [applyInitialGeometry] does.
  ///
  /// Never throws and never hangs past [_setupTimeout]: `main.dart` awaits
  /// this before flipping the app ready, and a startup screen with no
  /// timeout and no error state of its own must not be the thing a failure
  /// here leaves the user staring at forever. A failure - thrown or timed
  /// out - is logged and swallowed, matching [restoreSession]'s own
  /// precedent; the app reaches a usable window with no tray, no custom
  /// title bar and no geometry persistence rather than no window at all.
  static Future<void> registerListenersAndTray(
    ProviderContainer container,
  ) async {
    final platform = currentDesktopPlatform();
    if (platform == null) return;
    _active = true;
    try {
      await _bringUpWindowAndTray(container, platform).timeout(_setupTimeout);
    } catch (error, stack) {
      container
          .read(debugLogProvider.notifier)
          .record(
            'desktop',
            'window shell setup failed: $error',
            detail: stack,
          );
    }
  }

  static Future<void> _bringUpWindowAndTray(
    ProviderContainer container,
    DesktopPlatform platform,
  ) async {
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
      onShow: (action) => _offerFirstRunNoticeIfNeeded(container, action),
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

  /// [action] is null on a show that was never preceded by a routed close
  /// on this controller (the very first launch) - nothing happened yet to
  /// describe, so there is nothing to offer.
  static Future<void> _offerFirstRunNoticeIfNeeded(
    ProviderContainer container,
    CloseAction? action,
  ) async {
    if (action == null) return;
    final notice = await container.read(firstRunTrayNoticeProvider.future);
    if (notice.hasBeenShown(action)) return;
    container.read(firstRunTrayNoticeCloseActionProvider.notifier).state =
        action;
  }
}
