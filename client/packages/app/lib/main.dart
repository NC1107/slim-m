// SPDX-License-Identifier: Apache-2.0
/// The slim-m client.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import 'src/providers/providers.dart';
import 'src/providers/push_controller.dart';
import 'src/providers/sync_controller.dart';
import 'src/routing/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
