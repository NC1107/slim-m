// SPDX-License-Identifier: Apache-2.0
/// Routing.
///
/// A shell route wraps the signed-in surfaces so the channel list stays mounted
/// while the conversation changes, rather than the whole tree rebuilding on each
/// navigation. Paths come from [Routes]; no string literals appear at call sites.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../screens/admin/channel_overwrites_screen.dart';
import '../screens/admin/invites_screen.dart';
import '../screens/admin/reports_screen.dart';
import '../screens/admin/roles_screen.dart';
import '../screens/home_shell.dart';
import '../screens/settings_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/sign_in_screen.dart';
import '../screens/voice_settings_screen.dart';
import 'routes.dart';

/// The app's router.
///
/// Redirection is driven by the session, so a revoked session lands the user on
/// sign-in wherever they were, without any screen needing to check for itself.
final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionProvider);

  return GoRouter(
    initialLocation: Routes.onboarding,
    // Rebuilds the redirect whenever the session changes, which is what makes
    // sign-out and revocation take effect immediately.
    refreshListenable: _SessionListenable(ref),
    redirect: (context, state) {
      final signedIn = session.isSignedIn;
      final location = state.matchedLocation;
      final onJoinFlow =
          location == Routes.signIn || location == Routes.onboarding;
      // Signed out belongs in the join flow; signed in never does.
      if (!signedIn) return onJoinFlow ? null : Routes.onboarding;
      if (onJoinFlow) return Routes.channels;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => OnboardingScreen(
          onServerChosen: (server, invite) {
            ref.read(serverUrlProvider.notifier).state = server;
            ref.read(pendingInviteProvider.notifier).state = invite;
            context.go(Routes.signIn);
          },
        ),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: Routes.voiceSettings,
        builder: (context, state) => const VoiceSettingsScreen(),
      ),
      GoRoute(
        path: Routes.adminReports,
        builder: (context, state) => const ReportsScreen(),
      ),
      GoRoute(
        path: Routes.adminInvites,
        builder: (context, state) => const InvitesScreen(),
      ),
      GoRoute(
        path: Routes.adminRoles,
        builder: (context, state) => const RolesScreen(),
      ),
      GoRoute(
        path: Routes.adminOverwrites,
        builder: (context, state) => const ChannelOverwritesScreen(),
      ),
      // The shell keeps the channel list alive across conversation changes.
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: Routes.channels,
            builder: (context, state) => const NoChannelSelected(),
            routes: [
              GoRoute(
                path: ':channelId',
                builder: (context, state) => ConversationPane(
                  channelId: state.pathParameters['channelId']!,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Bridges the session stream to a Listenable, which is what GoRouter's
/// refresh hook takes.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    _subscription = ref.watch(sessionProvider).changes.listen((_) {
      notifyListeners();
    });
    ref.onDispose(() => _subscription.cancel());
  }

  late final dynamic _subscription;
}
