// SPDX-License-Identifier: Apache-2.0
/// Ties every other file in this directory into the calls `main.dart` makes:
/// put the window into small splash mode before it is ever shown, wire up
/// close-to-tray, geometry persistence and the tray icon once the app has a
/// [ProviderContainer] to read the running call's state from, then hand off
/// from the splash to the real, fully-sized window once bootstrap finishes.
///
/// A no-op on every platform but Linux, macOS and Windows: `main.dart` calls
/// every method here unconditionally, and each returns immediately off
/// [currentDesktopPlatform] being null rather than making every call site
/// guard itself.
///
/// See the superseding section of `docs/decisions/0012-desktop-window-shell.md`
/// for why the splash is a real small window rather than the full-size first
/// frame that record originally described.
library;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  /// The splash's fixed size - room for the 64px brand mark, the wordmark
  /// and a status line, no more - and deliberately unrelated to
  /// [WindowGeometry]: the splash is always this size, regardless of what
  /// the real window's own saved geometry turns out to be. See the startup
  /// screen (`startup_screen.dart`) and decision 0012's superseding section.
  static const splashWindowSize = WindowSize(width: 380, height: 460);

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

  /// True only once the native frame has actually been hidden - on Linux,
  /// set by [applyInitialGeometry] itself, before the splash's own first
  /// frame, so there is no native frame to see even during the splash. Stays
  /// true (or false, on a failure) for the rest of the run: nothing resets
  /// it back at handoff, since the splash and the ready app share the one
  /// real window and its one frame state throughout.
  static bool get frameless => _framelessApplied;

  /// The close button drawn inside [TitleBar] has no native close event of
  /// its own to reach [DesktopWindowController.requestClose] through, so it
  /// calls this instead - a no-op if the shell was never started. [frameless]
  /// no longer guarantees this is non-null the way it once did: it is now set
  /// during [applyInitialGeometry], before [registerListenersAndTray] ever
  /// creates the controller, so a native/tray failure in between can leave
  /// the window frameless with a close button that does nothing. `Ctrl+Q`
  /// (`desktop_quit_shortcut.dart`) is the deliberate, unconditional
  /// fallback for exactly that gap, registered independently of both.
  static Future<void> requestClose() =>
      _controller?.requestClose() ?? Future<void>.value();

  /// Puts the window into small splash mode before it is ever shown, so
  /// there is nothing to visibly jump once it appears - `main.dart` calls
  /// this before `runApp`, ahead of the startup screen's own first frame.
  /// The real, saved geometry is not read here at all: it is applied later,
  /// by [prepareHandoff], once bootstrap actually finishes.
  ///
  /// Bounded by [_setupTimeout] and never throws, for the same reason
  /// [registerListenersAndTray] is not allowed to: this runs before `runApp`,
  /// so a native window or display call that hangs (a portal or compositor
  /// not answering at the instant of launch) would otherwise block the first
  /// frame forever - a silent-forever startup screen strictly worse than the
  /// one that method already guards, since not even an empty window paints.
  /// On a timeout or error the window simply opens at its native default. No
  /// [ProviderContainer] exists this early, so the breadcrumb goes to
  /// [debugPrint] rather than the app log this file uses elsewhere.
  static Future<void> applyInitialGeometry() async {
    final platform = currentDesktopPlatform();
    if (platform == null) return;
    try {
      await _applySplashGeometry(platform).timeout(_setupTimeout);
    } catch (error) {
      debugPrint('desktop: initial splash geometry failed: $error');
    }
  }

  static Future<void> _applySplashGeometry(DesktopPlatform platform) async {
    await _port.ensureInitialized();
    await _port.setResizable(false);
    await _port.setSize(splashWindowSize);
    await _port.center();
    // Linux ships the frameless bar first, hidden ahead of the splash's own first frame; see decision 0012.
    if (platform == DesktopPlatform.linux) {
      await _port.hideTitleBar();
      _framelessApplied = true;
    }
  }

  /// Hides the window, then applies the real saved-or-default geometry (size,
  /// position where the platform has one, and maximized/fullscreen run
  /// state) while nothing is on screen to see it change - the traded-off
  /// stand-in for what a genuine second top-level window would give for
  /// free (one window gone, the other already there). Pair with
  /// [revealAfterHandoff], called only after the real UI has actually
  /// painted, so `show()` never uncovers a stale splash frame or an empty
  /// one. `main.dart` calls this once bootstrap resolves, before flipping
  /// `appReadyProvider`.
  ///
  /// Bounded and swallowed the same way [applyInitialGeometry] is: a hang or
  /// throw here must not strand the app hidden with nothing to reveal it.
  static Future<void> prepareHandoff(ProviderContainer container) async {
    if (currentDesktopPlatform() == null) return;
    try {
      await _applyFinalGeometry(container).timeout(_setupTimeout);
    } catch (error) {
      debugPrint('desktop: splash handoff geometry failed: $error');
    }
  }

  static Future<void> _applyFinalGeometry(ProviderContainer container) async {
    await _port.hide();

    final prefs = await container.read(preferencesProvider.future);
    final saved = WindowGeometryStore(prefs).read() ?? WindowGeometry.fallback;
    final geometry = clampToAttachedDisplays(saved, await _port.allDisplays());

    await _port.setResizable(true);
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

  /// Shows the window again after [prepareHandoff] applied the real geometry
  /// and `appReadyProvider` flipped - waits for the swapped-in real UI to
  /// actually paint first ([SchedulerBinding.endOfFrame]), so the window
  /// never reappears onto a stale splash frame or a blank one. `main.dart`
  /// calls this right after flipping `appReadyProvider` true.
  ///
  /// Bounded by [_setupTimeout] even though a real host always paints a
  /// frame on its own: leaving the window hidden forever on an unexpected
  /// stall would be strictly worse than the slow-splash failure modes
  /// [applyInitialGeometry] and [prepareHandoff] already guard against, so
  /// this shows the window regardless once the wait times out.
  static Future<void> revealAfterHandoff() async {
    if (currentDesktopPlatform() == null) return;
    try {
      await SchedulerBinding.instance.endOfFrame.timeout(_setupTimeout);
    } catch (error) {
      debugPrint('desktop: splash handoff frame wait failed: $error');
    }
    try {
      await _port.show();
    } catch (error) {
      debugPrint('desktop: splash handoff reveal failed: $error');
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
    // The Linux title bar is already hidden by applyInitialGeometry; see decision 0012's superseding section.

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
