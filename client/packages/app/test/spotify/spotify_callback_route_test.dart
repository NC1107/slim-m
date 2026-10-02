// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The Spotify redirect through the real router: the OS hands the URL to
/// Flutter's route information as well as to the deep-link stream, and the
/// person must stay on the screen they were on.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/routing/router.dart';
import 'package:slimm_app/src/routing/routes.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access-1',
  refreshToken: 'refresh-1',
  accessExpiresAt: 0,
);

void main() {
  testWidgets('the redirect never navigates away from Settings', (
    tester,
  ) async {
    final db = SlimmDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        databaseProvider.overrideWith((ref) => db),
        apiProvider.overrideWith((ref) {
          final api = SlimmApi(
            baseUrl: ref.watch(serverUrlProvider),
            session: ref.watch(sessionProvider),
            httpClient: MockClient(
              (_) async => http.Response(jsonEncode({}), 200),
            ),
          );
          ref.onDispose(api.close);
          return api;
        }),
      ],
    );
    container
        .read(chosenServerProvider.notifier)
        .restore(Uri.parse('https://chat.example'));
    container.read(sessionProvider).set(_tokens);
    final router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: buildTheme(Brightness.light, AppTokens.light),
          routerConfig: router,
        ),
      ),
    );
    router.go(Routes.personalSettings);
    await tester.pump();
    await tester.pump();
    expect(router.state.matchedLocation, Routes.personalSettings);

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(
        const MethodCall('pushRouteInformation', {
          'location': 'slimm://spotify-callback?code=c&state=s',
        }),
      ),
      (_) {},
    );
    await tester.pump();
    await tester.pump();

    final after = router.routerDelegate.currentConfiguration;
    expect(after.uri.path, Routes.personalSettings, reason: '${after.uri}');
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });
}
