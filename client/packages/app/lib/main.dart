// SPDX-License-Identifier: Apache-2.0
/// The slim-m client.
library;

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

import 'src/desktop/desktop_chrome.dart';
import 'src/desktop/desktop_quit_shortcut.dart';
import 'src/desktop/desktop_window_shell.dart';
import 'src/providers/attachment_preview_quality.dart';
import 'src/providers/media_preferences.dart';
import 'src/providers/message_page_size.dart';
import 'src/providers/image_cache_preference.dart';
import 'src/desktop/splash_floor.dart';
import 'src/desktop/startup_screen.dart';
import 'src/diagnostics/debug_log.dart';
import 'src/providers/display_preferences.dart';
import 'src/providers/notification_tap_router.dart';
import 'src/providers/providers.dart';
import 'src/providers/push_controller.dart';
import 'src/providers/sync_controller.dart';
import 'src/providers/voice_controller.dart';
import 'src/push/android_push_messages.dart';
import 'src/routing/router.dart';
import 'src/widgets/toast_overlay.dart';

/// Entry point.
///
/// [DesktopWindowShell.applyInitialGeometry] runs before [runApp] on purpose:
/// it is the one step that has to land before the very first Flutter frame
/// paints, or the startup screen below would flash at the OS default size
/// and then visibly jump to the last known one - a no-op on every platform
/// but a real desktop build. [DesktopWindowShell.registerSecondInstanceHandler]
/// runs right after it for the same reason: a launcher click racing this
/// process's own startup has to find a listener already in place.
/// [DesktopQuitShortcut.register] joins them here rather than waiting for
/// [_bootstrapApp]'s own tray setup, since it needs no [ProviderContainer]
/// and a quit combo pressed in the first instant the window is up should
/// already work.
///
/// Everything else that used to run here now runs inside [_bootstrapApp],
/// off the critical path to the first frame: [SlimMApp] shows [StartupApp]
/// while [appReadyProvider] is false and swaps to the real app once that
/// future resolves, so [restoreSession] still finishes before the router
/// ever builds - the same "no sign-in-then-jump" guarantee this file always
/// carried, just realised by a watched provider instead of an await ahead
/// of [runApp].
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initAndroidPush();
  await DesktopWindowShell.applyInitialGeometry();
  DesktopWindowShell.registerSecondInstanceHandler();
  DesktopQuitShortcut.register(DesktopWindowShell.port);

  final container = ProviderContainer();
  // Before anything that can throw, so startup failures land in the log too.
  installDiagnostics(container);

  container.read(appReadyProvider.notifier).state = false;
  unawaited(_bootstrapApp(container));

  runApp(
    UncontrolledProviderScope(container: container, child: const SlimMApp()),
  );
}

/// The async sequence [StartupApp] masks: session restore (so the router's
/// first redirect already knows the answer instead of showing sign-in and
/// jumping to channels a frame later), the six preference-controller
/// restores, sync/push bring-up, and the desktop window shell's own
/// listener/tray registration - a no-op on every platform but a real
/// desktop build. The sync and push controllers are read here rather than
/// left to whichever screen wants them first: they react to session changes
/// for their whole lives, and a restored session never passes through the
/// sign-in screen that would otherwise have touched them.
///
/// Wrapped in [awaitBootstrapWithSplashFloor] rather than flipping
/// [appReadyProvider] the instant this resolves: on desktop that sequence
/// can finish in a frame or two on a warm start, which is the exact reason
/// the startup screen went unnoticed - see `src/desktop/splash_floor.dart`.
Future<void> _bootstrapApp(ProviderContainer container) async {
  await awaitBootstrapWithSplashFloor(() => _runBootstrapSequence(container));
  container.read(appReadyProvider.notifier).state = true;
}

Future<void> _runBootstrapSequence(ProviderContainer container) async {
  await restoreSession(container);
  await container.read(themeControllerProvider.notifier).restore();
  await container.read(timeFormatControllerProvider.notifier).restore();
  await container.read(motionPreferenceControllerProvider.notifier).restore();
  await container.read(highContrastControllerProvider.notifier).restore();
  await container.read(imageCacheLimitControllerProvider.notifier).restore();
  await container
      .read(attachmentPreviewQualityControllerProvider.notifier)
      .restore();
  await container.read(mediaAutoDownloadControllerProvider.notifier).restore();
  await container.read(gifAutoplayControllerProvider.notifier).restore();
  await container.read(messagePageSizeControllerProvider.notifier).restore();
  await container
      .read(voiceControllerProvider.notifier)
      .restoreCameraPreference();
  await container
      .read(voiceControllerProvider.notifier)
      .restoreVoiceActivitySensitivity();
  await container
      .read(voiceControllerProvider.notifier)
      .restorePushToTalkPreference();
  container.read(syncControllerProvider);
  container.read(pushControllerProvider);
  await DesktopWindowShell.registerListenersAndTray(container);
}

/// Whether [_bootstrapApp] has finished. Defaults to true rather than false:
/// a test pumping `SlimMApp()` directly, with no call ever made into
/// [_bootstrapApp], sees the real app immediately, matching every existing
/// test's assumption - only the real entry point above ever sets it false
/// first.
final appReadyProvider = StateProvider<bool>((ref) => true);

/// Wires Firebase and the FCM background message handler Android needs to
/// ever show a notification while backgrounded or killed - the relay sends
/// data-only messages, so nothing appears unless this app builds it (see
/// `src/push/android_push_messages.dart`). Deliberately does not also listen
/// for foreground messages: see that file's doc for why a foreground push
/// never needs to show anything of its own.
///
/// Must run before [runApp], and the background handler must be registered
/// here specifically rather than from a provider or a widget: FCM invokes it
/// in its own isolate with no widget tree and no [ProviderContainer], so it
/// has to already be a reachable top-level function before that isolate can
/// exist. A no-op on iOS, Linux and the web, and best-effort even on Android:
/// a contributor's build with no `google-services.json` (see
/// `android/app/build.gradle.kts`) throws here, and push, like on iOS, must
/// never be the reason the rest of the app fails to start.
///
/// Swallowing that throw loses nothing, because the same missing credentials or
/// absent Play Services also degrade push registration through
/// `FcmTokenChannel`, and showing notifications cannot work without a token to
/// register in the first place.
Future<void> _initAndroidPush() async {
  if (!isAndroidHost) return;
  try {
    await ensureFirebaseInitialized();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (_) {
    // No Firebase credentials or no Play Services: push degrades either way.
  }
}

/// The root. Which surface is shown follows the session, enforced by the
/// router's redirect: a revoked session lands on sign-in from wherever the user
/// was, without any screen checking for itself. How it looks follows the
/// stored appearance choice, which is restored before the first frame.
class SlimMApp extends ConsumerWidget {
  const SlimMApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(appReadyProvider)) return const StartupApp();

    final choice = ref.watch(themeControllerProvider);
    final highContrast = ref.watch(highContrastControllerProvider);
    final lightTokens = highContrast
        ? applyHighContrast(AppTokens.light)
        : AppTokens.light;
    final darkTokens = highContrast
        ? applyHighContrast(_darkTokensFor(choice))
        : _darkTokensFor(choice);

    // Watched rather than read: this is what mounts the tap listener, and a
    // notification tap has to reach the router from outside the widget tree.
    ref.watch(notificationTapRouterProvider);

    return MaterialApp.router(
      title: 'slim-m',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, lightTokens),
      darkTheme: buildTheme(Brightness.dark, darkTokens),
      // Without this line MaterialApp's own ThemeMode.system default applies,
      // and no choice the user makes can reach the theme; that is what shipped.
      themeMode: _themeModeFor(choice),
      // Theme switching is on the motion spec's never-animates list, and
      // Material lerps it over 200ms by default.
      themeAnimationDuration: Duration.zero,
      routerConfig: ref.watch(routerProvider),
      // Material's own list rows are sized for a thumb whatever the window,
      // which is what made the settings and administration screens read as a
      // phone blown up. Applied here rather than per screen so a new one
      // cannot forget, and read from the window so nothing has to say which.
      builder: appChromeBuilder,
    );
  }
}

/// The one wrapper every top-level `MaterialApp` in this app must apply.
///
/// Pulled out of [SlimMApp.build] so the UI snapshot test harness can import
/// and reuse this exact function rather than rebuilding its own copy: a copy
/// is what previously let the harness render every desktop settings and
/// admin screen at touch density, silently, because it had drifted from what
/// this file actually wraps the router in.
///
/// This is also where [MotionPreferenceController]'s choice reaches
/// [AppMotion.isReduced]: a [Consumer] wrapping the whole routed tree in a
/// [MediaQuery] carrying [overrideMotion]'s answer, rather than a change to
/// [AppMotion] itself, which stays a pure read of whatever `MediaQuery` it is
/// given - the same choke point every animated widget already asks.
///
/// [DesktopChrome] is the outermost layer: the frameless title bar and the
/// first-run tray notice, both no-ops unless [DesktopWindowShell.active] -
/// never true in a plain `flutter test` run, which is what keeps this from
/// changing the tree shape of every other test in this package.
Widget appChromeBuilder(BuildContext context, Widget? child) => Consumer(
  builder: (context, ref, _) {
    final densityWrapped = ListTileTheme.merge(
      dense: !AppTouchTargets.of(context),
      child: child ?? const SizedBox.shrink(),
    );
    final motionChoice = ref.watch(motionPreferenceControllerProvider);
    return DesktopChrome(
      child: MediaQuery(
        data: overrideMotion(MediaQuery.of(context), motionChoice),
        // Above the routed tree and its dialogs and sheets, under the motion override.
        child: Stack(
          children: [
            densityWrapped,
            const Positioned.fill(child: ToastOverlay()),
          ],
        ),
      ),
    );
  },
);

ThemeMode _themeModeFor(AppThemeChoice choice) => switch (choice) {
  AppThemeChoice.system => ThemeMode.system,
  AppThemeChoice.light => ThemeMode.light,
  AppThemeChoice.dark || AppThemeChoice.trueBlack => ThemeMode.dark,
};

/// True black is a third palette rather than a fourth mode: it is the dark
/// theme built from a different token set, so it needs no second dark slot
/// that MaterialApp does not have.
AppTokens _darkTokensFor(AppThemeChoice choice) =>
    choice == AppThemeChoice.trueBlack ? AppTokens.trueBlack : AppTokens.dark;
