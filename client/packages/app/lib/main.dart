// SPDX-License-Identifier: Apache-2.0
/// The slim-m client.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import 'src/routing/router.dart';

void main() => runApp(const ProviderScope(child: SlimMApp()));

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
