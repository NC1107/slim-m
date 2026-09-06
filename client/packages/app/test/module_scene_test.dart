// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The scene contract that lets a module draw: parsing an output string into a
/// scene, resolving named colours, hit-testing a tap, and stepping the
/// interactive view through an injected runner.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/widgets/module_scene.dart';
import 'package:slimm_app/src/widgets/module_scene_painter.dart';
import 'package:slimm_app/src/widgets/module_scene_view.dart';
import 'package:slimm_design_system/design_system.dart';

String _lifeScene({
  int cols = 3,
  int rows = 3,
  String data = '000010000',
  String state = '3,3,0,000010000',
  String status = 'Generation 0 · 1 alive',
  bool live = true,
}) => jsonEncode({
  r'$slim': 'scene/1',
  'width': cols,
  'height': rows,
  'background': 'surface',
  'ops': [
    {
      'op': 'cells',
      'cols': cols,
      'rows': rows,
      'data': data,
      'palette': ['sunken', 'accent'],
      'gap': 0.1,
      'tap': 'toggle',
    },
  ],
  'state': state,
  'controls': ['play', 'step', 'random', 'clear'],
  'status': status,
  'live': live,
});

void main() {
  group('parseModuleScene', () {
    test('returns null for plain text', () {
      expect(parseModuleScene('hello world'), isNull);
      expect(parseModuleScene('  not a scene'), isNull);
    });

    test('returns null for malformed json', () {
      expect(parseModuleScene('{not json'), isNull);
    });

    test('returns null when the tag is missing or wrong', () {
      expect(parseModuleScene('{"foo":1}'), isNull);
      expect(parseModuleScene('{"\$slim":"scene/2"}'), isNull);
    });

    test('parses a life scene', () {
      final scene = parseModuleScene(_lifeScene())!;
      expect(scene.width, 3);
      expect(scene.height, 3);
      expect(scene.live, isTrue);
      expect(scene.state, '3,3,0,000010000');
      expect(scene.status, 'Generation 0 · 1 alive');
      expect(scene.controls, ['play', 'step', 'random', 'clear']);
      final op = scene.ops.single as CellsOp;
      expect(op.cols, 3);
      expect(op.rows, 3);
      expect(op.data.length, 9);
      expect(op.palette, ['sunken', 'accent']);
      expect(op.tap, 'toggle');
    });

    test('parses rect, circle, line and text ops and skips unknown ones', () {
      final scene = parseModuleScene(
        jsonEncode({
          r'$slim': 'scene/1',
          'width': 100,
          'height': 100,
          'ops': [
            {
              'op': 'rect',
              'x': 1,
              'y': 2,
              'w': 3,
              'h': 4,
              'fill': '#ff0000',
              'tap': 'a',
            },
            {'op': 'circle', 'cx': 5, 'cy': 6, 'r': 7},
            {'op': 'line', 'x1': 0, 'y1': 0, 'x2': 9, 'y2': 9},
            {'op': 'text', 's': 'hi', 'x': 1, 'y': 1},
            {'op': 'mystery'},
          ],
        }),
      )!;
      expect(scene.ops.length, 4);
      expect(scene.ops[0], isA<RectOp>());
      expect((scene.ops[0] as RectOp).tap, 'a');
      expect(scene.ops[1], isA<CircleOp>());
      expect(scene.ops[2], isA<LineOp>());
      expect((scene.ops[3] as TextOp).text, 'hi');
    });
  });

  group('resolveSceneColor', () {
    final tokens = AppTokens.light;
    test('parses hex literals', () {
      expect(
        resolveSceneColor('#ff0000', tokens, tokens.accent),
        const Color(0xffff0000),
      );
      expect(
        resolveSceneColor('#f00', tokens, tokens.accent),
        const Color(0xffff0000),
      );
    });

    test('resolves theme token names', () {
      expect(
        resolveSceneColor('accent', tokens, tokens.textPrimary),
        tokens.accent,
      );
      expect(
        resolveSceneColor('sunken', tokens, tokens.textPrimary),
        tokens.surfaceSunken,
      );
    });

    test('falls back for unknown names and null', () {
      expect(resolveSceneColor('nope', tokens, tokens.accent), tokens.accent);
      expect(resolveSceneColor(null, tokens, tokens.accent), tokens.accent);
    });
  });

  group('sceneTapAction', () {
    test('maps a tap on a cells grid to its row and column', () {
      final scene = parseModuleScene(
        _lifeScene(cols: 4, rows: 4, data: '0' * 16),
      )!;
      // A 4x4 grid in a 100x100 box: each cell is 25 wide. (60, 30) is col 2, row 1.
      final action = sceneTapAction(
        scene,
        const Offset(60, 30),
        const Size(100, 100),
      );
      expect(action, 'toggle:1,2');
    });

    test('returns null outside the grid', () {
      final scene = parseModuleScene(
        _lifeScene(cols: 4, rows: 4, data: '0' * 16),
      )!;
      expect(
        sceneTapAction(scene, const Offset(-5, -5), const Size(100, 100)),
        isNull,
      );
    });

    test('returns null when the op declares no tap', () {
      final scene = parseModuleScene(
        jsonEncode({
          r'$slim': 'scene/1',
          'width': 10,
          'height': 10,
          'ops': [
            {
              'op': 'cells',
              'cols': 2,
              'rows': 2,
              'data': '0000',
              'palette': ['sunken'],
            },
          ],
        }),
      )!;
      expect(
        sceneTapAction(scene, const Offset(1, 1), const Size(10, 10)),
        isNull,
      );
    });
  });

  group('ModuleSceneView', () {
    testWidgets('steps the scene through the runner', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var calls = 0;
      String? lastInput;
      Future<api.RunModuleCommandResult> run(String input) async {
        calls++;
        lastInput = input;
        return api.RunModuleCommandResult(
          ok: true,
          output: _lifeScene(
            state: '3,3,1,000111000',
            status: 'Generation 1 · 3 alive',
          ),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: Scaffold(
            body: ModuleSceneView(
              initial: parseModuleScene(_lifeScene())!,
              runCommand: run,
            ),
          ),
        ),
      );

      expect(find.text('Generation 0 · 1 alive'), findsOneWidget);

      await tester.tap(find.byIcon(AppIcons.forward));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(jsonDecode(lastInput!)['action'], 'step');
      expect(jsonDecode(lastInput!)['state'], '3,3,0,000010000');
      expect(find.text('Generation 1 · 3 alive'), findsOneWidget);
    });

    testWidgets('a new seed state resets the view', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<api.RunModuleCommandResult> run(String input) async =>
          const api.RunModuleCommandResult(ok: true, output: 'x');

      Widget wrap(String scene) => MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(
          body: ModuleSceneView(
            initial: parseModuleScene(scene)!,
            runCommand: run,
          ),
        ),
      );

      await tester.pumpWidget(
        wrap(_lifeScene(status: 'Generation 0 · 1 alive')),
      );
      expect(find.text('Generation 0 · 1 alive'), findsOneWidget);

      await tester.pumpWidget(
        wrap(
          _lifeScene(
            state: '3,3,0,111000000',
            status: 'Generation 0 · 3 alive',
          ),
        ),
      );
      expect(find.text('Generation 0 · 3 alive'), findsOneWidget);
    });
  });
}
