// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A tapped `slimm://` invite link, routed into the join flow.
///
/// The scheme is registered per platform (Android intent filter, iOS and
/// macOS `CFBundleURLTypes`, the Linux desktop entry's `x-scheme-handler`),
/// so the OS hands a tapped link to the app; this file is the receiving
/// half. A link only ever *fills the join flow in* - `parseInviteLink`'s
/// own doc explains why it must never skip the checks typing has to clear,
/// and that holds exactly as much for a tap as for a paste.
///
/// A link that arrives while signed in is deliberately ignored. One
/// deployment is one community in v1, so "join another server" while signed
/// in is a server switch - a product decision (sign out first? multiple
/// accounts?) that a background URL handler has no standing to make. The
/// signed-out case is the one a shared invite actually serves: the friend
/// being invited does not have an account yet.
///
/// Windows note: receiving these needs the scheme in the registry, which is
/// an installer concern the repo's packaging does not cover yet; pasting
/// the link into the join dialog remains the Windows path.
library;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'invite_link.dart';
import 'providers/providers.dart';
import 'routing/router.dart';
import 'routing/routes.dart';

/// The invite a tapped link carried, waiting for the onboarding screen to
/// consume it (it opens the redeem dialog prefilled and resets this to
/// null). Null whenever no tap is pending.
final tappedInviteProvider = StateProvider<({Uri server, String code})?>(
  (ref) => null,
);

/// The platform's deep-link URIs. `app_links` replays the launching link to
/// a new subscriber, so one stream covers both a cold start from a tap and
/// a tap while running. Overridden in tests; empty on web, where the
/// "link" is the page's own URL and the router already owns it.
final deepLinkUrisProvider = Provider<Stream<Uri>>(
  (ref) => kIsWeb ? const Stream.empty() : AppLinks().uriLinkStream,
);

/// What a delivered URI should do, decided purely so a test can pin it:
/// the parsed invite to prefill, or null to ignore the link entirely.
({Uri server, String code})? inviteFromDeepLink(
  Uri uri, {
  required bool signedIn,
}) {
  if (signedIn) return null;
  return parseInviteLink(uri.toString());
}

/// Listens for the app's whole lifetime; read once from bootstrap, next to
/// the sync and push controllers.
final deepLinkControllerProvider = Provider<void>((ref) {
  final sub = ref.read(deepLinkUrisProvider).listen((uri) {
    final invite = inviteFromDeepLink(
      uri,
      signedIn: ref.read(sessionProvider).isSignedIn,
    );
    if (invite == null) return;
    ref.read(tappedInviteProvider.notifier).state = invite;
    // The redirect keeps a signed-out user inside the join flow, so this can only land somewhere the invite is usable.
    ref.read(routerProvider).go(Routes.onboarding);
  });
  ref.onDispose(sub.cancel);
});
