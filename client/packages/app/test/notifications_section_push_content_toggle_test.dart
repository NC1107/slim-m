// SPDX-License-Identifier: Apache-2.0
/// The "show message text on your lock screen" toggle `NotificationsSection`
/// carries: iOS-only (see `personal_status_sections.dart`'s own doc comment
/// on `_PushContentPreviewRow` for why), persisted, and wired to trigger a
/// fresh `PUT /push` carrying the new answer rather than leaving the server
/// holding whatever this device last registered with.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/push_content_preview_settings.dart';
import 'package:slimm_app/src/providers/push_controller.dart';
import 'package:slimm_app/src/widgets/personal_status_sections.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

const _label = 'Show message text on your lock screen';

/// The native push channel mocked here so a real `_registerWithServer` call
/// can actually complete, the same channel `push_controller_test.dart` mocks
/// for the same reason.
const _pushChannel = MethodChannel('top.npcserver.slimm/push');

void _mockToken() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pushChannel, (call) async {
        return switch (call.method) {
          'getToken' => 'abcd1234',
          _ => null,
        };
      });
}

ProviderContainer _container({
  http.Client? httpClient,
  SessionStore? session,
  bool withApnsChannel = false,
}) {
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      if (session != null) sessionProvider.overrideWithValue(session),
      if (withApnsChannel)
        apnsTokenChannelProvider.overrideWithValue(
          ApnsTokenChannel(isIOS: true),
        ),
      if (httpClient != null)
        apiProvider.overrideWith((ref) {
          final api = SlimmApi(
            baseUrl: Uri.parse('http://localhost:8080'),
            session: ref.watch(sessionProvider),
            httpClient: httpClient,
          );
          ref.onDispose(api.close);
          return api;
        }),
    ],
  );
  container.read(preferencesProvider);
  return container;
}

Widget _shell(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: Scaffold(body: SingleChildScrollView(child: NotificationsSection())),
  ),
);

/// Runs [body] with [defaultTargetPlatform] overridden to [platform], and
/// always restores it before returning - never in `tearDown`, which runs
/// too late: `TestWidgetsFlutterBinding._verifyInvariants` asserts every
/// debug var is back to null the instant a `testWidgets` body returns,
/// strictly before any `tearDown`/`addTearDown` callback runs.
Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// Disposes [container] inline, not via `addTearDown`: a successful
/// registration starts a real `Timer.periodic` foreground heartbeat
/// (`PushController._startForegroundHeartbeat`), and `_verifyInvariants`
/// asserts none is pending the instant a `testWidgets` body returns,
/// strictly before any `tearDown` callback runs - the same ordering trap
/// [_withPlatform] guards against for a debug var.
void _disposeBeforeReturning(ProviderContainer container) =>
    container.dispose();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pushChannel, null);
  });

  testWidgets('absent on a non-iOS platform', (tester) async {
    await _withPlatform(TargetPlatform.android, () async {
      await tester.pumpWidget(_shell(_container()));
      await tester.pumpAndSettle();

      expect(find.text(_label), findsNothing);
    });
  });

  testWidgets('present, and off by default, on iOS', (tester) async {
    await _withPlatform(TargetPlatform.iOS, () async {
      await tester.pumpWidget(_shell(_container()));
      await tester.pumpAndSettle();

      final toggle = tester.widget<AppToggle>(
        find.byWidgetPredicate(
          (w) => w is AppToggle && w.semanticLabel == _label,
        ),
      );
      expect(toggle.value, isFalse);
    });
  });

  testWidgets('turning it on persists the preference', (tester) async {
    await _withPlatform(TargetPlatform.iOS, () async {
      await tester.pumpWidget(_shell(_container()));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is AppToggle && w.semanticLabel == _label,
        ),
      );
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(pushIncludeContentKey), isTrue);
    });
  });

  testWidgets(
    'turning it on re-registers with the server, carrying the new answer',
    (tester) async {
      await _withPlatform(TargetPlatform.iOS, () async {
        _mockToken();
        Map<String, dynamic>? sentBody;
        final container = _container(
          session: SessionStore(tokens: _tokens),
          withApnsChannel: true,
          httpClient: MockClient((request) async {
            if (request.method == 'PUT' && request.url.path == '/push') {
              sentBody = jsonDecode(request.body) as Map<String, dynamic>;
            }
            return http.Response('', 204);
          }),
        );
        await tester.pumpWidget(_shell(container));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is AppToggle && w.semanticLabel == _label,
          ),
        );
        await tester.pumpAndSettle();

        expect(sentBody, isNotNull);
        expect(sentBody!['include_content'], isTrue);

        _disposeBeforeReturning(container);
      });
    },
  );

  testWidgets('carries its own accessible name, verified against the real '
      'semantics tree rather than assumed from the widget', (tester) async {
    await _withPlatform(TargetPlatform.iOS, () async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_shell(_container()));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(_label), findsOneWidget);
      handle.dispose();
    });
  });
}
