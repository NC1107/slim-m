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
import '../screens/admin/analytics_screen.dart';
import '../screens/admin/categories_screen.dart';
import '../screens/admin/channel_overwrites_screen.dart';
import '../screens/admin/emoji_screen.dart';
import '../screens/admin/invites_screen.dart';
import '../screens/admin/reports_screen.dart';
import '../screens/admin/removed_members_screen.dart';
import '../screens/admin/roles_screen.dart';
import '../screens/home_shell.dart';
import '../screens/debug_log_screen.dart';
import '../screens/personal_settings_screen.dart';
import '../screens/space_settings_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/sign_in_screen.dart';
import '../screens/thread_screen.dart';
import 'modal_page.dart';
import 'page_transitions.dart';
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
  // Settings and administration are pushed over the app so they can float as
  // modals with it still visible behind. Without this the address bar would
  // keep saying /channels while a modal is open, so the URL could not be
  // copied, shared or reloaded, and browser back would not close it.
  GoRouter.optionURLReflectsImperativeAPIs = true;
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
      // The join flow fades through like the shell's own pages, so signing in hands off into the app as one motion.
      GoRoute(
        path: Routes.onboarding,
        pageBuilder: (context, state) => fadeThroughPage(
          context,
          OnboardingScreen(
            onServerChosen: (server, invite) {
              ref.read(chosenServerProvider.notifier).choose(server);
              ref.read(pendingInviteProvider.notifier).state = invite;
              context.go(Routes.signIn);
            },
          ),
          key: const ValueKey('onboarding'),
        ),
      ),
      GoRoute(
        path: Routes.signIn,
        pageBuilder: (context, state) => fadeThroughPage(
          context,
          const SignInScreen(),
          key: const ValueKey('sign-in'),
        ),
      ),
      GoRoute(
        path: Routes.personalSettings,
        pageBuilder: (context, state) =>
            modalPage(context, const PersonalSettingsScreen()),
      ),
      GoRoute(
        path: Routes.spaceSettings,
        pageBuilder: (context, state) =>
            modalPage(context, const SpaceSettingsScreen()),
      ),
      GoRoute(
        path: Routes.adminReports,
        pageBuilder: (context, state) =>
            modalPage(context, const ReportsScreen()),
      ),
      GoRoute(
        path: Routes.adminInvites,
        pageBuilder: (context, state) =>
            modalPage(context, const InvitesScreen()),
      ),
      GoRoute(
        path: Routes.adminRoles,
        pageBuilder: (context, state) =>
            modalPage(context, const RolesScreen()),
      ),
      GoRoute(
        path: Routes.adminRemovedMembers,
        pageBuilder: (context, state) =>
            modalPage(context, const RemovedMembersScreen()),
      ),
      GoRoute(
        path: Routes.adminOverwrites,
        pageBuilder: (context, state) =>
            modalPage(context, const ChannelOverwritesScreen()),
      ),
      GoRoute(
        path: Routes.adminCategories,
        pageBuilder: (context, state) =>
            modalPage(context, const CategoriesScreen()),
      ),
      GoRoute(
        path: Routes.adminEmoji,
        pageBuilder: (context, state) =>
            modalPage(context, const EmojiScreen()),
      ),
      GoRoute(
        path: Routes.adminAnalytics,
        pageBuilder: (context, state) =>
            modalPage(context, const AnalyticsScreen()),
      ),
      GoRoute(
        path: Routes.debugLog,
        pageBuilder: (context, state) =>
            modalPage(context, const DebugLogScreen()),
      ),
      GoRoute(
        path: Routes.threadPattern,
        pageBuilder: (context, state) => modalPage(
          context,
          ThreadScreen(channelId: state.pathParameters['channelId']!),
        ),
      ),
      // The shell keeps the channel list alive across conversation changes;
      // the child pages fade through so switching one for another reads as a
      // navigation rather than an instant swap.
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: Routes.channels,
            pageBuilder: (context, state) => fadeThroughPage(
              context,
              const NoChannelSelected(),
              key: const ValueKey('no-channel'),
            ),
            routes: [
              GoRoute(
                path: ':channelId',
                pageBuilder: (context, state) {
                  final channelId = state.pathParameters['channelId']!;
                  // Generously over a uuid's 36; see client_transport.dart.
                  if (channelId.length > 128) {
                    return fadeThroughPage(
                      context,
                      const NoChannelSelected(),
                      key: const ValueKey('no-channel'),
                    );
                  }
                  return fadeThroughPage(
                    context,
                    ConversationPane(channelId: channelId),
                    key: ValueKey('channel-$channelId'),
                  );
                },
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
