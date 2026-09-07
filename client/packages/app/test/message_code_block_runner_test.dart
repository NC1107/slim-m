// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The Run affordance on a fenced code block and its inline output, per
/// docs/decisions/0021-modules-and-the-dock.md's module-agnostic principle:
/// [MessageBody] itself never names a module, only whatever
/// `codeBlockRunnerProvider` hands back.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/code_block_runner.dart';
import 'package:slimm_app/src/providers/live_events.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/message_text.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

const _fenced = '```js\nconsole.log(1)\n```';

Future<void> _pump(
  WidgetTester tester, {
  required List<api.CodeBlockRunner> runners,
  http.Response Function(http.Request)? onRunRequest,
  String? messageId,
  Stream<api.ServerEvent>? events,
}) async {
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      if (events != null) liveEventsProvider.overrideWithValue(events),
      codeBlockRunnerProvider.overrideWith((ref) async => runners),
      apiProvider.overrideWith((ref) {
        final built = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            if (onRunRequest != null) return onRunRequest(request);
            return http.Response('', 404);
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
        home: Scaffold(
          body: MessageBody(
            content: _fenced,
            knownUsernames: const {},
            messageId: messageId,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

http.Response _jsonResponse(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  testWidgets('no runner available means no Run affordance at all', (
    tester,
  ) async {
    await _pump(tester, runners: const []);

    expect(find.bySemanticsLabel('Run code'), findsNothing);
  });

  testWidgets('a runner being available shows the Run affordance', (
    tester,
  ) async {
    await _pump(
      tester,
      runners: const [
        api.CodeBlockRunner(moduleId: 'code-exec', command: 'run'),
      ],
    );

    expect(find.bySemanticsLabel('Run code'), findsOneWidget);
  });

  testWidgets(
    'running posts the code and renders the output inline below the block',
    (tester) async {
      String? sentBody;
      await _pump(
        tester,
        runners: const [
          api.CodeBlockRunner(moduleId: 'code-exec', command: 'run'),
        ],
        onRunRequest: (request) {
          expect(request.method, 'POST');
          expect(request.url.path, '/modules/code-exec/commands/run');
          sentBody = request.body;
          return _jsonResponse({'ok': true, 'output': '1'});
        },
      );

      await tester.tap(find.bySemanticsLabel('Run code'));
      await tester.pumpAndSettle();

      expect(jsonDecode(sentBody!)['input'], 'console.log(1)');
      expect(find.text('Result'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    },
  );

  testWidgets(
    "the module's own ok:false renders as error output, not AppErrorState",
    (tester) async {
      await _pump(
        tester,
        runners: const [
          api.CodeBlockRunner(moduleId: 'code-exec', command: 'run'),
        ],
        onRunRequest: (_) =>
            _jsonResponse({'ok': false, 'error': 'syntax error'}),
      );

      await tester.tap(find.bySemanticsLabel('Run code'));
      await tester.pumpAndSettle();

      expect(find.text('Error'), findsOneWidget);
      expect(find.text('syntax error'), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
    },
  );

  testWidgets(
    'a transport-level failure surfaces via AppErrorState, never a SnackBar, '
    'and renders no output',
    (tester) async {
      await _pump(
        tester,
        runners: const [
          api.CodeBlockRunner(moduleId: 'code-exec', command: 'run'),
        ],
        onRunRequest: (_) =>
            _jsonResponse({'error': 'module is not enabled'}, 409),
      );

      await tester.tap(find.bySemanticsLabel('Run code'));
      await tester.pumpAndSettle();

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.textContaining('Module is not enabled'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Result'), findsNothing);
      expect(find.text('Error'), findsNothing);
    },
  );

  testWidgets('a second run replaces the previous output rather than adding '
      'to it', (tester) async {
    var call = 0;
    await _pump(
      tester,
      runners: const [
        api.CodeBlockRunner(moduleId: 'code-exec', command: 'run'),
      ],
      onRunRequest: (_) {
        call += 1;
        return _jsonResponse({'ok': true, 'output': 'run $call'});
      },
    );

    await tester.tap(find.bySemanticsLabel('Run code'));
    await tester.pumpAndSettle();
    expect(find.text('run 1'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Run code'));
    await tester.pumpAndSettle();
    expect(find.text('run 1'), findsNothing);
    expect(find.text('run 2'), findsOneWidget);
  });

  testWidgets(
    'a runner declared for a different language is never offered on this '
    'block',
    (tester) async {
      await _pump(
        tester,
        runners: const [
          api.CodeBlockRunner(
            moduleId: 'code-exec',
            command: 'run',
            language: 'python',
          ),
        ],
      );

      expect(find.bySemanticsLabel('Run code'), findsNothing);
    },
  );

  testWidgets(
    "a runner declared 'javascript' matches this block's 'js' fence tag "
    'through the alias map',
    (tester) async {
      await _pump(
        tester,
        runners: const [
          api.CodeBlockRunner(
            moduleId: 'code-exec',
            command: 'run',
            language: 'javascript',
          ),
        ],
      );

      expect(find.bySemanticsLabel('Run code'), findsOneWidget);
    },
  );

  testWidgets('the first matching runner wins when several are discovered', (
    tester,
  ) async {
    String? postedModuleId;
    await _pump(
      tester,
      runners: const [
        api.CodeBlockRunner(
          moduleId: 'first',
          command: 'run',
          language: 'javascript',
        ),
        api.CodeBlockRunner(
          moduleId: 'second',
          command: 'run',
          language: 'javascript',
        ),
      ],
      onRunRequest: (request) {
        postedModuleId = request.url.pathSegments[1];
        return _jsonResponse({'ok': true, 'output': 'done'});
      },
    );

    await tester.tap(find.bySemanticsLabel('Run code'));
    await tester.pumpAndSettle();

    expect(postedModuleId, 'first');
  });

  testWidgets(
    'a scene step in a message goes through the shared message-scoped route, '
    'not the ephemeral one, so every viewer sees it',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String scene(String state) =>
          '{"\$slim":"scene/1","width":3,"height":3,'
          '"ops":[{"op":"cells","cols":3,"rows":3,"data":"000010000",'
          '"palette":["sunken","accent"],"tap":"toggle"}],'
          '"controls":["step"],"state":"$state","live":true}';
      final events = StreamController<api.ServerEvent>.broadcast();
      addTearDown(events.close);
      final paths = <String>[];
      await _pump(
        tester,
        messageId: 'm1',
        events: events.stream,
        runners: const [
          api.CodeBlockRunner(moduleId: 'game-of-life', command: 'life'),
        ],
        onRunRequest: (request) {
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
                output: scene('s${paths.length}'),
                ranBy: 'u1',
                ranAt: 1700000000000 + paths.length,
              ),
            ),
          );
          return _jsonResponse({'ok': true, 'output': scene('s${paths.length}')});
        },
      );

      await tester.tap(find.bySemanticsLabel('Run code'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Step'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Step'));
      await tester.pumpAndSettle();

      expect(paths, isNotEmpty);
      expect(paths, everyElement('/messages/m1/blocks/0/run'));
      expect(
        paths.any((p) => p.contains('/commands/')),
        isFalse,
        reason: 'a step must not hit the ephemeral per-caller run endpoint',
      );
    },
  );
}
