// SPDX-License-Identifier: Apache-2.0
/// Tests for the settings screen's account actions: a failure partway
/// through sign-out or deletion must reach the screen, not vanish and leave
/// the user stranded. Also the presence visibility control, which is a real
/// endpoint now.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/presence_controller.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/settings_screen.dart';
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

Widget _screen(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: const SettingsScreen(),
  ),
);

void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'slim-m',
      packageName: 'top.npcserver.slimm',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('a failed account deletion is shown on screen, not silently left '
      'signed in with sync already stopped and the push key already gone', (
    tester,
  ) async {
    /// Signed out, so deleteAccount() (like every other authenticated call
    /// this screen makes) fails fast with UnauthorizedException before any
    /// request is sent; the point under test is that the failure reaches the
    /// screen instead of disappearing into an unhandled Future.
    final container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        apiProvider.overrideWith((ref) {
          final api = SlimmApi(
            baseUrl: Uri.parse('http://localhost:8080'),
            session: ref.watch(sessionProvider),
            httpClient: MockClient(
              (_) async => throw StateError('unexpected call'),
            ),
          );
          ref.onDispose(api.close);
          return api;
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    /// Below the fold on the default test viewport; the account section is
    /// last in the list. ListView builds every child eagerly, so the finder
    /// already resolves before any scrolling; drag directly rather than via
    /// scrollUntilVisible, which only scrolls until the finder resolves at
    /// all, not until the target is actually within the viewport. The drag
    /// is deliberately larger than the list's content: Flutter clamps to
    /// `maxScrollExtent` rather than erroring, so this reaches the bottom
    /// regardless of exactly how tall the sections above it are.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not delete the account'), findsOneWidget);
  });

  testWidgets('the whole screen lays out at phone width', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        apiProvider.overrideWith((ref) {
          final api = SlimmApi(
            baseUrl: Uri.parse('http://localhost:8080'),
            session: ref.watch(sessionProvider),
            httpClient: MockClient(
              (_) async => throw StateError('unexpected call'),
            ),
          );
          ref.onDispose(api.close);
          return api;
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Every section, not just the ones above the fold: the presence control
    // overflowed by 264pt here and no test viewport was ever this narrow.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

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

    // Presence now sits past the viewport's cache extent, so the option is
    // not merely off screen: it does not exist to be found until scrolled to.
    await tester.scrollUntilVisible(
      find.text('Away'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Away'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Away'));
    await tester.pumpAndSettle();

    expect(requests.where((u) => u.path == '/presence'), hasLength(1));
    expect(
      container.read(presenceVisibilityDisplayProvider),
      PresenceVisibility.away,
    );
  });

  // The regression: the overflow was fixed by scrolling the four options
  // horizontally, hiding two of them (one the privacy control) off the edge.
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
    await tester.scrollUntilVisible(
      find.text('Appear offline'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    for (final label in const [
      'Online',
      'Away',
      'Do not disturb',
      'Appear offline',
    ]) {
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(0.0), reason: '$label is cut off');
      expect(
        rect.right,
        lessThanOrEqualTo(390.0),
        reason: '$label runs past the right edge of the screen',
      );
    }

    // Reachable, not merely painted: an option outside the viewport takes no
    // tap, so this is what a horizontal scroll view could not satisfy.
    await tester.tap(find.text('Appear offline'));
    await tester.pumpAndSettle();
    expect(
      container.read(presenceVisibilityDisplayProvider),
      PresenceVisibility.hidden,
    );
    expect(requests.where((u) => u.path == '/presence'), hasLength(1));
  });
}
