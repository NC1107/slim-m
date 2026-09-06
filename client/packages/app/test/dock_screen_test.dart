// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The Dock: `GET /space/dock/modules`, `GET /space/dock/installed`, `GET
/// /space/dock/modules/{id}` and `POST .../install`. Exercises the real
/// client bindings through `SlimmApi` (a `MockClient` intercepts the HTTP
/// call itself), the same shape `storage_screen_test.dart` uses.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/admin/dock_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'admin',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

final _fakeSha256 = List.filled(64, 'a').join();

const _indexEntry = {
  'id': 'code-exec',
  'name': 'Code Blocks',
  'version': '1.2.0',
  'summary': 'Run code snippets in a channel and post the output.',
};

Map<String, dynamic> _manifest() => {
  ..._indexEntry,
  'author': 'slim-m',
  'artifact': {
    'kind': 'wasm',
    'path': 'modules/code-exec/1.2.0/module.wasm',
    'sha256': _fakeSha256,
  },
  'runtime': {
    'backend': 'wasm',
    'limits': {'memory_mb': 64, 'wall_ms': 2000, 'fuel': 500000000},
  },
  'permissions': [
    {
      'key': 'run',
      'name': 'Execute code blocks',
      'description': 'Submit a snippet to run in this space.',
    },
  ],
  'capabilities': ['command.register', 'message.post'],
  'extension_points': [
    {'kind': 'command', 'name': 'run'},
  ],
};

Map<String, dynamic> _installedRow({
  required bool enabled,
  List<Map<String, dynamic>> extensionPoints = const [],
}) => {
  'id': 'code-exec',
  'name': 'Code Blocks',
  'version': '1.2.0',
  'artifact_sha256': _fakeSha256,
  'approved_capabilities': ['command.register', 'message.post'],
  'extension_points': extensionPoints,
  'enabled': enabled,
  'installed_at': 1000,
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

ProviderContainer _containerFor(MockClient client) {
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      apiProvider.overrideWith((ref) {
        final built = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: client,
        );
        ref.onDispose(built.close);
        return built;
      }),
    ],
  );
  return container;
}

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildTheme(Brightness.dark, AppTokens.dark),
    home: const Scaffold(body: DockScreen()),
  ),
);

void main() {
  testWidgets('browsing lists a module with its version, summary and state', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path == '/space/dock/modules') {
        return _json([_indexEntry]);
      }
      if (request.url.path == '/space/dock/installed') {
        return _json(<Map<String, dynamic>>[]);
      }
      throw StateError('unexpected request: ${request.method} ${request.url}');
    });
    final container = _containerFor(client);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    expect(find.text('Code Blocks'), findsOneWidget);
    expect(find.text('v1.2.0'), findsOneWidget);
    expect(
      find.text('Run code snippets in a channel and post the output.'),
      findsOneWidget,
    );
    // Not installed anywhere yet, so no state badge is drawn.
    expect(find.text('Enabled'), findsNothing);
    expect(find.text('Disabled'), findsNothing);
  });

  testWidgets('opening a module and installing it shows the install as done', (
    tester,
  ) async {
    var installed = false;
    String? installedPath;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/space/dock/modules') {
        return _json([_indexEntry]);
      }
      if (path == '/space/dock/installed') {
        return _json(installed ? [_installedRow(enabled: false)] : <Object>[]);
      }
      if (path == '/space/dock/modules/code-exec') {
        return _json(_manifest());
      }
      if (path == '/space/dock/modules/code-exec/install' &&
          request.method == 'POST') {
        installedPath = path;
        installed = true;
        return _json(_installedRow(enabled: false));
      }
      throw StateError('unexpected request: ${request.method} ${request.url}');
    });
    final container = _containerFor(client);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    // The only row on screen, so its "view" action is the only chevron.
    await tester.tap(find.byIcon(AppIcons.chevronRight));
    await tester.pumpAndSettle();

    // Before install, its manifest shows the permission it adds and the capability it asks for.
    expect(find.text('Execute code blocks'), findsOneWidget);
    expect(
      find.text('COMMAND.REGISTER'),
      findsOneWidget,
      reason: 'capability badge (AppBadge renders its label uppercased)',
    );
    expect(find.text('Install v1.2.0'), findsOneWidget);

    await tester.tap(find.text('Install v1.2.0'));
    await tester.pumpAndSettle();

    expect(installedPath, '/space/dock/modules/code-exec/install');
    // Installed (disabled by default): the sheet now offers enable/disable and uninstall, not "Install".
    expect(find.text('Install v1.2.0'), findsNothing);
    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Uninstall'), findsOneWidget);
  });

  testWidgets(
    'an installed and enabled module with a command extension point shows '
    'a run panel that posts input and renders output',
    (tester) async {
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path == '/space/dock/modules') {
          return _json([_indexEntry]);
        }
        if (path == '/space/dock/installed') {
          return _json([
            _installedRow(
              enabled: true,
              extensionPoints: [
                {
                  'kind': 'command',
                  'name': 'run',
                  'description': 'Runs a snippet.',
                  'permission': 'run',
                },
              ],
            ),
          ]);
        }
        if (path == '/space/dock/modules/code-exec') {
          return _json(_manifest());
        }
        if (path == '/modules/code-exec/commands/run' &&
            request.method == 'POST') {
          expect(jsonDecode(request.body)['input'], 'console.log(1)');
          return _json({'ok': true, 'output': '1'});
        }
        throw StateError(
          'unexpected request: ${request.method} ${request.url}',
        );
      });
      final container = _containerFor(client);
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.chevronRight));
      await tester.pumpAndSettle();

      expect(find.text('Runs a snippet.'), findsOneWidget);

      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'console.log(1)');
      await tester.ensureVisible(find.text('Run'));
      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();

      expect(find.text('Output'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    },
  );

  testWidgets(
    'a 403 from running a command surfaces via AppErrorState, never a '
    'SnackBar',
    (tester) async {
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path == '/space/dock/modules') {
          return _json([_indexEntry]);
        }
        if (path == '/space/dock/installed') {
          return _json([
            _installedRow(
              enabled: true,
              extensionPoints: [
                {
                  'kind': 'command',
                  'name': 'run',
                  'description': 'Runs a snippet.',
                  'permission': 'run',
                },
              ],
            ),
          ]);
        }
        if (path == '/space/dock/modules/code-exec') {
          return _json(_manifest());
        }
        if (path == '/modules/code-exec/commands/run' &&
            request.method == 'POST') {
          return _json({'error': 'forbidden'}, 403);
        }
        throw StateError(
          'unexpected request: ${request.method} ${request.url}',
        );
      });
      final container = _containerFor(client);
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.chevronRight));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'console.log(1)');
      await tester.ensureVisible(find.text('Run'));
      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.textContaining('not allowed'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'a disabled module never shows a command panel even if it declares one',
    (tester) async {
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path == '/space/dock/modules') {
          return _json([_indexEntry]);
        }
        if (path == '/space/dock/installed') {
          return _json([
            _installedRow(
              enabled: false,
              extensionPoints: [
                {
                  'kind': 'command',
                  'name': 'run',
                  'description': 'Runs a snippet.',
                  'permission': 'run',
                },
              ],
            ),
          ]);
        }
        if (path == '/space/dock/modules/code-exec') {
          return _json(_manifest());
        }
        throw StateError(
          'unexpected request: ${request.method} ${request.url}',
        );
      });
      final container = _containerFor(client);
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.chevronRight));
      await tester.pumpAndSettle();

      expect(find.text('Runs a snippet.'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets(
    'a failed fetch surfaces through the persistent error state, never a '
    'SnackBar',
    (tester) async {
      final client = MockClient((request) async => http.Response('', 500));
      final container = _containerFor(client);
      addTearDown(container.dispose);

      await tester.pumpWidget(_app(container));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not reach the module marketplace.'),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
    },
  );
}
