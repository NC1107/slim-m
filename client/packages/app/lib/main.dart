// SPDX-License-Identifier: Apache-2.0
/// The slim-m client.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

import 'src/providers/providers.dart';
import 'src/providers/push_controller.dart';
import 'src/providers/sync_controller.dart';
import 'src/push/android_push_messages.dart';
import 'src/routing/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initAndroidPush();

  final container = ProviderContainer();
  // Local-only, so it cannot hang startup on a dead connection; see
  // restoreSession. Doing this before runApp is what lets the router's very
  // first redirect already know the answer, instead of showing sign-in and
  // then jumping to channels a frame later.
  await restoreSession(container);
  // These react to session changes for their whole lives: push retries on
  // resume, sync starts and stops with the session. Reading them here keeps
  // that reaction alive for a restored session, which never passes through
  // the sign-in screen that would otherwise have touched them.
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
Future<void> _initAndroidPush() async {
  if (!isAndroidHost) return;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (_) {
    // No Firebase credentials, or no Play Services on this device: push
    // registration itself degrades the same way through FcmTokenChannel, and
    // showing notifications simply cannot work without a token to register
    // in the first place.
  }
}

/// The root. Which surface is shown follows the session, enforced by the
/// router's redirect: a revoked session lands on sign-in from wherever the user
/// was, without any screen checking for itself.
class SlimMApp extends ConsumerWidget {
  const SlimMApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'slim-m',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, AppTokens.light),
      darkTheme: buildTheme(Brightness.dark, AppTokens.dark),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
