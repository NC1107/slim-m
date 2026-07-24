// SPDX-License-Identifier: Apache-2.0
/// The slim-m client.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import 'src/providers/providers.dart';
import 'src/screens/home_shell.dart';
import 'src/screens/sign_in_screen.dart';

void main() => runApp(const ProviderScope(child: SlimMApp()));

/// The root. Which surface is shown follows the session: signed in gets the
/// shell, signed out gets sign-in, and a revoked session drops back
/// automatically because the session is a stream rather than a snapshot.
class SlimMApp extends ConsumerWidget {
  const SlimMApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(signedInProvider);

    return MaterialApp(
      title: 'slim-m',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, AppTokens.light),
      darkTheme: buildTheme(Brightness.dark, AppTokens.dark),
      home: signedIn.maybeWhen(
        orElse: () => const SignInScreen(),
        data: (isSignedIn) =>
            isSignedIn ? const HomeShell() : const SignInScreen(),
      ),
    );
  }
}
