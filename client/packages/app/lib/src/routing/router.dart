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
/// Redirection is driven by two facts, not one. The session decides whether the
/// signed-in surfaces are reachable, so a revoked session lands the user on the
/// join flow wherever they were. Which end of that flow they land on is decided
/// by whether a server has ever been chosen: someone who already has one is
/// signed out, not new, and sending them to onboarding asks them to retype an
/// address the app is holding.
final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionProvider);

  // Read, not watched: main() awaits restoreSession before the router is
  // built, so a remembered server is already in place by this point.
  String signedOutHome() => ref.read(chosenServerProvider) == null
      ? Routes.onboarding
      : Routes.signIn;

  return GoRouter(
    initialLocation: signedOutHome(),
    // Rebuilds the redirect whenever the session changes, which is what makes
    // sign-out and revocation take effect immediately.
    refreshListenable: _SessionListenable(ref),
    redirect: (context, state) {
      final signedIn = session.isSignedIn;
      final location = state.matchedLocation;
      final onJoinFlow =
          location == Routes.signIn || location == Routes.onboarding;
      // Anywhere in the join flow is left alone, so a signed-out user can walk
      // back to onboarding to pick a different server or redeem an invite.
      if (!signedIn) return onJoinFlow ? null : signedOutHome();
      if (onJoinFlow) return Routes.channels;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => OnboardingScreen(
          onServerChosen: (server, invite) {
            ref.read(chosenServerProvider.notifier).choose(server);
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
