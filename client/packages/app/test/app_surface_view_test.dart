// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// [AppSurfaceView] launches its module's command on mount and every step
/// through the message-scoped, shared code-run route, never the ephemeral
/// per-caller one - so a launched app is the same evolving surface for everyone
/// viewing the message, per docs/decisions/0021's module-agnostic principle.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/live_events.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/app_surface_view.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

String _scene(String state) =>
    '{"\$slim":"scene/1","width":3,"height":3,'
    '"ops":[{"op":"cells","cols":3,"rows":3,"data":"000010000",'
    '"palette":["sunken","accent"],"tap":"toggle"}],'
    '"controls":["step"],"state":"$state","live":true}';

void main() {
  testWidgets(
    'launches on mount and steps through the shared message-scoped route',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final events = StreamController<api.ServerEvent>.broadcast();
      addTearDown(events.close);
      final paths = <String>[];

      final container = ProviderContainer(
        overrides: [
          keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
          sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
          liveEventsProvider.overrideWithValue(events.stream),
          apiProvider.overrideWith((ref) {
            final built = api.SlimmApi(
              baseUrl: Uri.parse('http://localhost:8080'),
              session: ref.watch(sessionProvider),
              httpClient: MockClient((request) async {
                paths.add(request.url.path);
                // The shared render comes from the broadcast (extras), so feed one.
                events.add(
                  api.CodeRunChanged(
                    channelId: 'c1',
                    messageId: 'm1',
                    run: api.CodeRun(
                      blockIndex: 0,
                      moduleId: 'game-of-life',
                      command: 'life',
                      ok: true,
                      output: _scene('s${paths.length}'),
                      ranBy: 'u1',
                      ranAt: 1700000000000 + paths.length,
                    ),
                  ),
                );
                return http.Response(
                  jsonEncode({
                    'ok': true,
                    'output': _scene('s${paths.length}'),
                  }),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }),
            );
            ref.onDispose(built.close);
            return built;
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildTheme(Brightness.light, AppTokens.light),
            home: const Scaffold(
              body: AppSurfaceView(
                messageId: 'm1',
                surface: api.AppSurface(
                  moduleId: 'game-of-life',
                  command: 'life',
                ),
                title: 'game-of-life',
              ),
            ),
          ),
        ),
      );
      // The post-frame auto-run needs a settle to fire and its broadcast to land.
      await tester.pumpAndSettle();

      expect(
        paths,
        isNotEmpty,
        reason: 'it should launch itself on mount without a tap',
      );
      expect(find.bySemanticsLabel('Step'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Step'));
      await tester.pumpAndSettle();

      expect(paths.length, greaterThanOrEqualTo(2));
      expect(paths, everyElement('/messages/m1/blocks/0/run'));
      expect(
        paths.any((p) => p.contains('/commands/')),
        isFalse,
        reason: 'a launch or step must not hit the ephemeral run endpoint',
      );
    },
  );
}
