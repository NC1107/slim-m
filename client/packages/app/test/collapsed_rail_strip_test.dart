// SPDX-License-Identifier: Apache-2.0
/// Tests for [CollapsedRailStrip]: what replaces the channel rail once it is
/// collapsed at a wide layout (`home_shell.dart`'s `AnimatedContainer`
/// branch). The rail itself unmounts when collapsed on purpose - see
/// `channelRailVisibleProvider`'s own doc, it polls voice rosters while
/// built - so the hard requirement here is that this strip never brings
/// [ChannelRail] back with it, on top of the ordinary "does it work" cases.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/sync_controller.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/routing/routes.dart';
import 'package:slimm_app/src/screens/home_shell.dart';
import 'package:slimm_app/src/widgets/channel_rail.dart';
import 'package:slimm_app/src/widgets/collapsed_rail_strip.dart';
import 'package:slimm_app/src/widgets/rail_drag_handle.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';

import 'voice_controller_harness.dart' show FixedVoiceController;

class _NoopSyncController extends SyncController {
  _NoopSyncController(super.ref);

  @override
  Future<void> start() async {}
}

const _tokens = api.TokenPair(
  userId: 'bob',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

MockClient _quietClient() => MockClient((request) async {
  final Object body = request.url.path == '/me'
      ? {
          'id': 'bob',
          'username': 'bob',
          'display_name': 'Bob',
          'created_at': 0,
          'permissions': 0,
        }
      : const <Object>[];
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
});

/// Collapsed from the first frame ([channelRailVisibleProvider] overridden
/// to `false`), with [voiceState] standing in for whatever call the app is
/// or is not in, the same seam `FixedVoiceController` exists for.
({ProviderContainer container, SlimmDatabase db}) _setup(
  VoiceState voiceState,
) {
  final db = SlimmDatabase(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      syncControllerProvider.overrideWith((ref) => _NoopSyncController(ref)),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: _quietClient(),
        );
        ref.onDispose(client.close);
        return client;
      }),
      databaseProvider.overrideWith((ref) => db),
      channelRailVisibleProvider.overrideWith((ref) => false),
      voiceControllerProvider.overrideWith(
        (ref) => FixedVoiceController(ref, voiceState),
      ),
    ],
  );
  return (container: container, db: db);
}

Future<void> _teardown(
  WidgetTester tester,
  ProviderContainer container,
  SlimmDatabase db,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
  container.dispose();
  await db.close();
}

/// Personal settings gets its own route here, unlike most shell suites: this
/// is the one thing this strip has to actually reach for the assertion to
/// mean anything.
GoRouter _router(String location) => GoRouter(
  initialLocation: location,
  routes: [
    ShellRoute(
      builder: (context, state, child) => HomeShell(child: child),
      routes: [
        GoRoute(
          path: '/channels',
          builder: (context, state) => const Center(child: Text('no-channel')),
          routes: [
            GoRoute(
              path: ':channelId',
              builder: (context, state) => Center(
                child: Text('channel:${state.pathParameters['channelId']}'),
              ),
            ),
          ],
        ),
        GoRoute(
          path: Routes.personalSettings,
          builder: (context, state) =>
              const Scaffold(body: Text('personal-settings-screen')),
        ),
      ],
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  String location = '/channels/c1',
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildTheme(Brightness.light, AppTokens.light),
        routerConfig: _router(location),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the collapsed rail shows the strip in place of ChannelRail, never both',
    (tester) async {
      final s = _setup(const VoiceState());
      await _pump(tester, s.container);

      expect(find.byType(CollapsedRailStrip), findsOneWidget);
      expect(
        find.byType(ChannelRail),
        findsNothing,
        reason:
            'ChannelRail polls voice rosters while built; the collapsed '
            'strip must be a lightweight stand-in, not ChannelRail at a '
            'narrow width',
      );

      await _teardown(tester, s.container, s.db);
    },
  );

  testWidgets('the strip carries settings, mic and deafen controls', (
    tester,
  ) async {
    final s = _setup(const VoiceState());
    await _pump(tester, s.container);

    expect(find.bySemanticsLabel('Personal settings'), findsOneWidget);
    expect(find.byIcon(AppIcons.mic), findsOneWidget);
    expect(find.byIcon(AppIcons.headphones), findsOneWidget);

    await _teardown(tester, s.container, s.db);
  });

  testWidgets(
    'the expand affordance is RailDragHandle, still on screen and working '
    'beside the strip - the strip does not duplicate its icon or label',
    (tester) async {
      final s = _setup(const VoiceState());
      await _pump(tester, s.container);

      expect(find.byType(RailDragHandle), findsOneWidget);
      expect(find.byIcon(AppIcons.sidebar), findsOneWidget);
      expect(find.bySemanticsLabel('Expand channel list'), findsOneWidget);

      await tester.tap(find.byType(RailDragHandle));
      await tester.pumpAndSettle();

      expect(find.byType(ChannelRail), findsOneWidget);
      expect(find.byType(CollapsedRailStrip), findsNothing);
      await _teardown(tester, s.container, s.db);
    },
  );

  testWidgets('tapping settings on the strip opens personal settings', (
    tester,
  ) async {
    final s = _setup(const VoiceState());
    await _pump(tester, s.container);

    await tester.tap(find.bySemanticsLabel('Personal settings'));
    await tester.pumpAndSettle();

    expect(find.text('personal-settings-screen'), findsOneWidget);
    await _teardown(tester, s.container, s.db);
  });

  testWidgets(
    'in a call, mic and deafen are enabled and reach the voice controller',
    (tester) async {
      final s = _setup(
        const VoiceState(state: VoiceSessionState.connected, channelId: 'c1'),
      );
      await _pump(tester, s.container);
      final controller = s.container.read(voiceControllerProvider.notifier);

      expect(controller.state.microphoneEnabled, isTrue);
      await tester.tap(find.bySemanticsLabel('Mute'));
      await tester.pumpAndSettle();
      expect(
        controller.state.microphoneEnabled,
        isFalse,
        reason: 'the strip must call the real toggleMicrophone, not a copy',
      );

      expect(controller.state.deafened, isFalse);
      await tester.tap(find.bySemanticsLabel('Deafen'));
      await tester.pumpAndSettle();
      expect(
        controller.state.deafened,
        isTrue,
        reason: 'the strip must call the real toggleDeafen, not a copy',
      );

      await _teardown(tester, s.container, s.db);
    },
  );

  testWidgets('outside a call, mic and deafen are disabled', (tester) async {
    final s = _setup(const VoiceState());
    await _pump(tester, s.container);

    final mic = tester.widget<AppIconButton>(
      find.ancestor(
        of: find.byIcon(AppIcons.mic),
        matching: find.byType(AppIconButton),
      ),
    );
    final deafen = tester.widget<AppIconButton>(
      find.ancestor(
        of: find.byIcon(AppIcons.headphones),
        matching: find.byType(AppIconButton),
      ),
    );
    expect(mic.onPressed, isNull);
    expect(deafen.onPressed, isNull);

    await _teardown(tester, s.container, s.db);
  });
}
