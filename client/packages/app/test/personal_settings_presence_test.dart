// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The presence visibility control inside the "Account & presence" pane.
///
/// Split out of `personal_settings_screen_test.dart`, which crossed the
/// 500-line hard ceiling; these four tests are a self-contained group about
/// one control rather than the screen's own structure.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/presence_controller.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/personal_settings_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _signedIn = TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// A signed-in container whose every request is answered, so the presence
/// section renders alongside the rest of the screen rather than beside error
/// states that would change the layout under test. Every request lands in
/// [requests].
ProviderContainer _signedInContainer(List<Uri> requests) {
  return ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(SessionStore(tokens: _signedIn)),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            requests.add(request.url);
            if (request.url.path == '/devices' ||
                request.url.path == '/blocks') {
              return http.Response(
                '[]',
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.path == '/me') {
              return http.Response(
                jsonEncode({
                  'id': 'self',
                  'username': 'self',
                  'display_name': 'Self',
                  'created_at': 0,
                  'permissions': 0,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode({'visibility': 'away'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        ref.onDispose(api.close);
        return api;
      }),
    ],
  );
}

/// Like [_signedInContainer], but `/presence` refuses every request.
ProviderContainer _signedInContainerFailingPresence(List<Uri> requests) {
  return ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(SessionStore(tokens: _signedIn)),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            requests.add(request.url);
            if (request.url.path == '/devices' ||
                request.url.path == '/blocks') {
              return http.Response(
                '[]',
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.path == '/me') {
              return http.Response(
                jsonEncode({
                  'id': 'self',
                  'username': 'self',
                  'display_name': 'Self',
                  'created_at': 0,
                  'permissions': 0,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.path == '/presence') {
              return http.Response(
                '{}',
                500,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              '{}',
              404,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        ref.onDispose(api.close);
        return api;
      }),
    ],
  );
}

Widget _screen(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: const PersonalSettingsScreen(),
  ),
);

void main() {
  testWidgets('picking a presence option sends it and updates the display', (
    tester,
  ) async {
    final requests = <Uri>[];
    final container = _signedInContainer(requests);
    addTearDown(container.dispose);

    await tester.pumpWidget(_screen(container));
    await tester.pumpAndSettle();

    /// Null, not Online: no endpoint reports a caller's own visibility back,
    /// and the preference is durable server-side, so claiming online here
    /// would tell someone still hidden that they are visible.
    expect(container.read(presenceVisibilityDisplayProvider), isNull);

    // Past the cache extent: it does not exist to be found until scrolled to.
    await tester.scrollUntilVisible(
      find.text('Status'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Away').last);
    await tester.pumpAndSettle();

    expect(requests.where((u) => u.path == '/presence'), hasLength(1));
    expect(
      container.read(presenceVisibilityDisplayProvider),
      PresenceVisibility.away,
    );
  });

  testWidgets(
    'an unresolved visibility reads as its own "Not set", not Online',
    (tester) async {
      final requests = <Uri>[];
      final container = _signedInContainer(requests);
      addTearDown(container.dispose);

      await tester.pumpWidget(_screen(container));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Status'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Status'));
      await tester.pumpAndSettle();

      expect(
        find.text('Online'),
        findsNothing,
        reason:
            'a value this client cannot read back must never read as the '
            'most public choice',
      );
      expect(
        find.text('Not set'),
        findsOneWidget,
        reason:
            'the unresolved state reads as a deliberate "no choice yet", not '
            'the row default "Unknown" that reads as an error on a fresh '
            'account (UX6)',
      );
      expect(find.text('Unknown'), findsNothing);
    },
  );

  testWidgets('a refused presence change keeps the last known choice and '
      'reports the failure, rather than reading as Online', (tester) async {
    final requests = <Uri>[];
    final container = _signedInContainerFailingPresence(requests);
    addTearDown(container.dispose);
    container.read(presenceVisibilityDisplayProvider.notifier).state =
        PresenceVisibility.away;

    await tester.pumpWidget(_screen(container));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Status'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appear offline').last);
    await tester.pumpAndSettle();

    expect(
      container.read(presenceVisibilityDisplayProvider),
      PresenceVisibility.away,
      reason:
          'a refusal must restore the last choice, never keep the one '
          'the server rejected',
    );
    expect(find.text('Online'), findsNothing);
    expect(find.text('Away'), findsOneWidget);
    expect(find.byType(AppErrorState), findsOneWidget);
  });

  // Once fixed by scrolling the four options horizontally; a sheet now.
  testWidgets('every presence option is on screen and tappable at 390pt', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final requests = <Uri>[];
    final container = _signedInContainer(requests);
    addTearDown(container.dispose);

    await tester.pumpWidget(_screen(container));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account & presence'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();

    for (final label in const [
      'Online',
      'Away',
      'Do not disturb',
      'Appear offline',
    ]) {
      final rect = tester.getRect(find.text(label).last);
      expect(rect.left, greaterThanOrEqualTo(0.0), reason: '$label is cut off');
      expect(
        rect.right,
        lessThanOrEqualTo(390.0),
        reason: '$label runs past the right edge of the screen',
      );
    }

    // Reachable, not merely painted: a horizontal scroll view could not do this.
    await tester.tap(find.text('Appear offline'));
    await tester.pumpAndSettle();
    expect(
      container.read(presenceVisibilityDisplayProvider),
      PresenceVisibility.hidden,
    );
    expect(requests.where((u) => u.path == '/presence'), hasLength(1));
  });
}
