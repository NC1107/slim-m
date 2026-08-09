// SPDX-License-Identifier: Apache-2.0
/// `_changePicture` (`avatar_settings_section.dart`) calls `setActionError`
/// when the native picker throws, but nothing clears that error at the
/// start of the *next* attempt the way `composer.dart`'s own
/// `_pickAttachment` now does (see the commit fixing exactly that shape
/// there). A retry that this time opens the picker without throwing, but
/// where the user then picks nothing, returns early with the earlier
/// failure still on screen - stale, since the picker just demonstrably
/// worked.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/avatar_settings_section.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

/// The badge's own `InkWell`, found through the camera glyph it always
/// carries rather than through its `Semantics` label: once `AppErrorState`
/// is also on screen, `tester.tap(find.bySemanticsLabel(...))` no longer
/// lands the tap on the real badge, so this finder is what the second half
/// of the reproduction below actually needed to get past the first defect
/// and reach the one this file is about.
Finder _cameraBadge() => find.ancestor(
  of: find.byIcon(AppIcons.avatarCamera),
  matching: find.byType(InkWell),
);

const _tokens = TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

const _filePickerChannel = MethodChannel(
  'miguelruivo.flutter.plugins.filepicker',
);

void main() {
  testWidgets(
    'a picker retry that opens fine, even with nothing picked, clears the '
    'earlier open failure',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_filePickerChannel, (call) async {
            throw PlatformException(code: 'no_portal', message: 'no portal');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_filePickerChannel, null),
      );

      final container = ProviderContainer(
        overrides: [
          keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
          sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
          apiProvider.overrideWith((ref) {
            final api = SlimmApi(
              baseUrl: Uri.parse('http://localhost:8080'),
              session: ref.watch(sessionProvider),
              httpClient: MockClient((request) async {
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
                return http.Response('', 404);
              }),
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
            home: const Scaffold(body: AvatarSettingsSection()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_cameraBadge());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photo library'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not open the file picker'),
        findsOneWidget,
        reason: 'the first, real failure must still be said',
      );

      // The channel now answers rather than throws, the same shape a
      // cancelled pick returns - the picker opened and closed with nothing
      // chosen, not a repeat of the earlier failure.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_filePickerChannel, (call) async => null);

      await tester.tap(_cameraBadge());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photo library'));
      await tester.pumpAndSettle();

      expect(
        find.byType(AppErrorState),
        findsNothing,
        reason:
            'reproduction: a picker that just opened successfully must not '
            'keep reading as still-broken because an earlier attempt threw',
      );
    },
  );
}
