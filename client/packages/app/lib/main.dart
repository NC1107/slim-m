// SPDX-License-Identifier: Apache-2.0
/// The slim-m client.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

import 'src/diagnostics/debug_log.dart';
import 'src/providers/providers.dart';
import 'src/providers/push_controller.dart';
import 'src/providers/sync_controller.dart';
import 'src/push/android_push_messages.dart';
import 'src/routing/router.dart';

/// Entry point, with two ordering constraints that are not obvious from the
/// statements themselves.
///
/// [restoreSession] runs before [runApp] because it is local-only and so cannot
/// hang startup on a dead connection (see its own doc), and because doing it
/// first is what lets the router's very first redirect already know the answer,
/// instead of showing sign-in and then jumping to channels a frame later.
///
/// The sync and push controllers are read here rather than left to whichever
/// screen happens to want them: they react to session changes for their whole
/// lives (push retries on resume, sync starts and stops with the session), and
/// a restored session never passes through the sign-in screen that would
/// otherwise have touched them.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initAndroidPush();

  final container = ProviderContainer();
  // Before anything that can throw, so startup failures land in the log too.
  installDiagnostics(container);
  // Before runApp so the router's first redirect knows the answer.
  await restoreSession(container);
  // Awaited for the same reason, and free: restoreSession has already
  // resolved the preference store this reads from.
  await container.read(themeControllerProvider.notifier).restore();

  /// These react to session changes for their whole lives: push retries on
  /// resume, sync starts and stops with the session. Reading them here keeps
  /// that reaction alive for a restored session, which never passes through
  /// the sign-in screen that would otherwise have touched them.
  container.read(syncControllerProvider);
  container.read(pushControllerProvider);

  runApp(
    UncontrolledProviderScope(container: container, child: const SlimMApp()),
  );
}

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
    await Firebase.initializeApp();
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
    final choice = ref.watch(themeControllerProvider);

    return MaterialApp.router(
      title: 'slim-m',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, AppTokens.light),
      darkTheme: buildTheme(Brightness.dark, _darkTokensFor(choice)),
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
      builder: (context, child) => ListTileTheme.merge(
        dense: !AppTouchTargets.of(context),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

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
