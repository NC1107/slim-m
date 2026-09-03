// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A tapped `slimm://` invite link: what it does, and just as much what it
/// must not do.
///
/// The decision half (`inviteFromDeepLink`) is pinned pure. The glue half
/// is exercised through the real controller with the platform stream faked,
/// proving a delivered link sets [tappedInviteProvider] - and that the
/// signed-in and junk cases set nothing, so a background URL handler can
/// never yank a signed-in user out of their session.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/deep_links.dart';
import 'package:slimm_app/src/invite_link.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/routing/router.dart';
import 'package:slimm_platform/platform.dart';

void main() {
  final link = Uri.parse(
    buildInviteLink(server: Uri.parse('https://chat.example:8443'), code: 'C1'),
  );

  group('inviteFromDeepLink', () {
    test('a signed-out tap yields the parsed invite', () {
      final invite = inviteFromDeepLink(link, signedIn: false);
      expect(invite?.server, Uri.parse('https://chat.example:8443'));
      expect(invite?.code, 'C1');
    });

    test('a signed-in tap is ignored: joining elsewhere is a server '
        'switch, not a background navigation', () {
      expect(inviteFromDeepLink(link, signedIn: true), isNull);
    });

    test('a URI that is not an invite link is ignored', () {
      expect(
        inviteFromDeepLink(Uri.parse('slimm://other?x=1'), signedIn: false),
        isNull,
      );
      expect(
        inviteFromDeepLink(Uri.parse('https://chat.example'), signedIn: false),
        isNull,
      );
    });
  });

  group('deepLinkControllerProvider', () {
    ({ProviderContainer container, StreamController<Uri> uris}) harness({
      required bool signedIn,
    }) {
      final uris = StreamController<Uri>();
      // A minimal real router: go() must land somewhere without a tree.
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/join', builder: (_, _) => const SizedBox()),
        ],
      );
      addTearDown(router.dispose);
      final container = ProviderContainer(
        overrides: [
          keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
          routerProvider.overrideWithValue(router),
          deepLinkUrisProvider.overrideWithValue(uris.stream),
          if (signedIn)
            sessionProvider.overrideWithValue(
              api.SessionStore(
                tokens: const api.TokenPair(
                  userId: 'u-1',
                  accessToken: 't',
                  refreshToken: 'r',
                  accessExpiresAt: 0,
                ),
              ),
            ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(uris.close);
      container.read(deepLinkControllerProvider);
      return (container: container, uris: uris);
    }

    test('a delivered invite link is held for the join flow', () async {
      final h = harness(signedIn: false);
      h.uris.add(link);
      await Future<void>.delayed(Duration.zero);
      final held = h.container.read(tappedInviteProvider);
      expect(held?.code, 'C1');
      expect(held?.server, Uri.parse('https://chat.example:8443'));
      // The information provider, not the delegate: without a widget tree nothing processes the update further, but the intent is recorded here.
      expect(
        h.container
            .read(routerProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/join',
        reason: 'the tap must land the user on the join flow',
      );
    });

    test('while signed in nothing is held', () async {
      final h = harness(signedIn: true);
      h.uris.add(link);
      await Future<void>.delayed(Duration.zero);
      expect(h.container.read(tappedInviteProvider), isNull);
    });

    test('junk on the stream is ignored', () async {
      final h = harness(signedIn: false);
      h.uris.add(Uri.parse('slimm://join?code=only'));
      await Future<void>.delayed(Duration.zero);
      expect(h.container.read(tappedInviteProvider), isNull);
    });
  });
}
