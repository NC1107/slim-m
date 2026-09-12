// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Drawing on a scene, and the control that says whether it is playing.
///
/// A module call is a round trip and only one runs at a time, so a drag across
/// a grid produces cells faster than they can be sent. The `_busy` guard used
/// to drop everything that arrived mid-flight, which for a drag would mean a
/// line with holes in it, so cells queue and drain in order.
///
/// Pause is here for a related reason: it stopped the timer without repainting
/// the button, so the control kept drawing a pause glyph while the animation
/// had already stopped, and pressing it again started play while still showing
/// pause. The board going still was the only feedback either way.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/widgets/module_scene.dart';
import 'package:slimm_app/src/widgets/module_scene_view.dart';
import 'package:slimm_design_system/design_system.dart';

/// A 4x4 board whose cells answer `toggle`, the shape game-of-life sends.
///
/// [tapBatch] mirrors the module's own `tap_batch`: game-of-life 0.3.0 reads a
/// `;`-separated list of cells, 0.2.0 does not and answers "bad cell" to one.
String _scene(int gen, {bool live = true, bool tapBatch = false}) =>
    jsonEncode({
      r'$slim': 'scene/1',
      'width': 4,
      'height': 4,
      'ops': [
        {
          'op': 'cells',
          'cols': 4,
          'rows': 4,
          'data': '................',
          'tap': 'toggle',
          'tap_batch': tapBatch,
        },
      ],
      'state': 'g$gen',
      'controls': ['play', 'step'],
      'live': live,
    });

/// Mounts the view at a known size and records every action it sends.
Future<List<String>> _actionsFrom(
  WidgetTester tester,
  Future<void> Function(WidgetTester tester, Offset topLeft) drive, {
  Duration latency = Duration.zero,
  bool tapBatch = false,
}) async {
  final actions = <String>[];
  var gen = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark, AppTokens.dark),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: ModuleSceneView(
              initial: parseModuleScene(_scene(0, tapBatch: tapBatch))!,
              runCommand: (input) async {
                actions.add(jsonDecode(input)['action'] as String);
                if (latency > Duration.zero) {
                  await Future<void>.delayed(latency);
                }
                return api.RunModuleCommandResult(
                  ok: true,
                  output: _scene(++gen, tapBatch: tapBatch),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final board = find.descendant(
    of: find.byType(ModuleSceneView),
    matching: find.byType(CustomPaint),
  );
  // ignore: avoid_print
  print(
    'BOARD n=${board.evaluate().length} rect=${tester.getRect(board.last)}',
  );
  await drive(tester, tester.getTopLeft(board.last));
  await tester.pumpAndSettle();
  return actions;
}

/// Moves in 20px steps from [from] to [to]. A single long `moveTo` clears the
/// drag threshold in one jump, so `onPanStart` fires wherever it lands rather
/// than in the cell the finger actually started in - which no real drag does.
Future<void> _dragThrough(
  WidgetTester tester,
  Offset from,
  List<Offset> waypoints,
) async {
  final gesture = await tester.startGesture(from);
  var current = from;
  for (final target in waypoints) {
    final steps = ((target - current).distance / 20).ceil().clamp(1, 200);
    for (var i = 1; i <= steps; i++) {
      current = Offset.lerp(current, target, i / steps)!;
      await gesture.moveTo(current);
      await tester.pump();
    }
    current = target;
  }
  await gesture.up();
}

void main() {
  testWidgets('a rate limit while playing paces it instead of stopping it', (
    tester,
  ) async {
    // Playing outruns the write budget; a long run used to fail outright.
    var calls = 0;
    var gen = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: Scaffold(
          body: ModuleSceneView(
            initial: parseModuleScene(_scene(0))!,
            runCommand: (_) async {
              calls++;
              if (calls == 2) {
                throw const api.RateLimitedException('too many requests');
              }
              return api.RunModuleCommandResult(
                ok: true,
                output: _scene(++gen),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 140));
    }

    expect(
      find.bySemanticsLabel('Pause'),
      findsOneWidget,
      reason: 'a refusal for asking too fast must not stop the animation',
    );
    expect(
      find.byType(AppErrorState),
      findsNothing,
      reason: 'nor put an error in front of somebody watching a board play',
    );
    expect(calls, greaterThan(2), reason: 'it kept going after the refusal');

    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('a rate limit on a manual step still surfaces', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: Scaffold(
          body: ModuleSceneView(
            initial: parseModuleScene(_scene(0))!,
            runCommand: (_) async =>
                throw const api.RateLimitedException('too many requests'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Step'));
    await tester.pumpAndSettle();

    expect(
      find.byType(AppErrorState),
      findsOneWidget,
      reason: 'a press that did nothing has to say why; only play paces',
    );
  });

  testWidgets('the controls do not disable themselves mid-call', (
    tester,
  ) async {
    // Disabling on every in-flight call is what made them flash while playing.
    final completer = Completer<api.RunModuleCommandResult>();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: Scaffold(
          body: ModuleSceneView(
            initial: parseModuleScene(_scene(0))!,
            runCommand: (_) => completer.future,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Step'));
    await tester.pump();

    final step = tester.widget<AppIconButton>(
      find
          .ancestor(
            of: find.bySemanticsLabel('Step'),
            matching: find.byType(AppIconButton),
          )
          .first,
    );
    expect(
      step.onPressed,
      isNotNull,
      reason: 'greying out for the length of every generation is the flicker',
    );

    completer.complete(api.RunModuleCommandResult(ok: true, output: _scene(1)));
    await tester.pumpAndSettle();
  });

  testWidgets('play survives the shared path echoing each step back', (
    tester,
  ) async {
    // The shape a message-owned scene has: every action stores and broadcasts.
    var gen = 0;
    var latest = _scene(0);
    final actions = <String>[];
    late StateSetter rebuildHost;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setHostState) {
              rebuildHost = setHostState;
              return ModuleSceneView(
                initial: parseModuleScene(latest)!,
                runCommand: (input) async {
                  actions.add(jsonDecode(input)['action'] as String);
                  latest = _scene(++gen);
                  // The broadcast lands on the row that owns this widget.
                  rebuildHost(() {});
                  return api.RunModuleCommandResult(ok: true, output: latest);
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 140));
    }

    expect(
      actions.length,
      greaterThan(3),
      reason:
          'the widget stopped its own timer when its own step came back: '
          'played $actions',
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });

  testWidgets('a run somebody else started still resets and stops', (
    tester,
  ) async {
    // The other half of the guard: a state this view never produced is new.
    var latest = _scene(0);
    late StateSetter rebuildHost;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setHostState) {
              rebuildHost = setHostState;
              return ModuleSceneView(
                initial: parseModuleScene(latest)!,
                runCommand: (_) async =>
                    api.RunModuleCommandResult(ok: true, output: latest),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);

    // Nothing in flight, and a state this view has never seen.
    latest = _scene(999);
    rebuildHost(() {});
    await tester.pump();

    expect(
      find.bySemanticsLabel('Play'),
      findsOneWidget,
      reason: 'a foreign run must stop the animation, not inherit it',
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });

  testWidgets('a drag paints every cell it crosses, in order', (tester) async {
    // Roughly 100px a cell, so the row-0 centres sit near 50, 150, 250, 350.
    final actions = await _actionsFrom(tester, (tester, origin) async {
      final gesture = await tester.startGesture(origin + const Offset(50, 50));
      for (final dx in [150.0, 250.0, 350.0]) {
        await gesture.moveTo(origin + Offset(dx, 50));
        await tester.pump();
      }
      await gesture.up();
    });

    expect(actions, [
      'toggle:0,0',
      'toggle:0,1',
      'toggle:0,2',
      'toggle:0,3',
    ], reason: 'a dragged line must not have holes where the module was busy');
  });

  testWidgets('a drag still paints every cell when calls are slow', (
    tester,
  ) async {
    late List<String> actions;
    await tester.runAsync(() async {
      actions = await _actionsFrom(tester, (tester, origin) async {
        final gesture = await tester.startGesture(
          origin + const Offset(50, 50),
        );
        for (final dx in [150.0, 250.0, 350.0]) {
          await gesture.moveTo(origin + Offset(dx, 50));
          await tester.pump();
        }
        await gesture.up();
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
        }
      }, latency: const Duration(milliseconds: 40));
    });

    expect(
      actions.length,
      4,
      reason: 'the queue drains, it does not drop: $actions',
    );
  });

  testWidgets('a module that reads a list gets the drag in far fewer calls', (
    tester,
  ) async {
    // Latency is the point: cells only pile up behind a call already in flight.
    late List<String> actions;
    await tester.runAsync(() async {
      actions = await _actionsFrom(
        tester,
        (tester, origin) async {
          final gesture = await tester.startGesture(
            origin + const Offset(50, 50),
          );
          for (final dx in [150.0, 250.0, 350.0]) {
            await gesture.moveTo(origin + Offset(dx, 50));
            await tester.pump();
          }
          await gesture.up();
          for (var i = 0; i < 30; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump(const Duration(milliseconds: 20));
          }
        },
        latency: const Duration(milliseconds: 40),
        tapBatch: true,
      );
    });

    // The first cell goes alone; the rest ride together in the next call.
    expect(actions.length, lessThan(4), reason: 'sent $actions');
    expect(
      actions.last.split(';').length,
      greaterThan(1),
      reason: 'the tail should have been coalesced: $actions',
    );
    expect(actions.expand((a) => a.split(':').last.split(';')).toSet(), {
      '0,0',
      '0,1',
      '0,2',
      '0,3',
    }, reason: 'every cell still arrives, whatever the grouping');
  });

  testWidgets('a module that never said it reads a list still gets singles', (
    tester,
  ) async {
    // game-of-life 0.2.0's shape: a list would come back "bad cell".
    final actions = await _actionsFrom(tester, (tester, origin) async {
      final gesture = await tester.startGesture(origin + const Offset(50, 50));
      for (final dx in [150.0, 250.0, 350.0]) {
        await gesture.moveTo(origin + Offset(dx, 50));
        await tester.pump();
      }
      await gesture.up();
    });

    expect(actions, [
      'toggle:0,0',
      'toggle:0,1',
      'toggle:0,2',
      'toggle:0,3',
    ], reason: 'batching is opt-in, and an older module never opted in');
  });

  testWidgets('crossing a cell twice in one drag paints it once', (
    tester,
  ) async {
    final actions = await _actionsFrom(tester, (tester, origin) async {
      await _dragThrough(tester, origin + const Offset(50, 50), [
        origin + const Offset(150, 50),
        origin + const Offset(50, 50),
      ]);
    });

    expect(actions, [
      'toggle:0,0',
      'toggle:0,1',
    ], reason: 'a second crossing would toggle the cell back off');
  });

  testWidgets('pause repaints the control it belongs to', (tester) async {
    var gen = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: Scaffold(
          body: ModuleSceneView(
            initial: parseModuleScene(_scene(0))!,
            runCommand: (_) async =>
                api.RunModuleCommandResult(ok: true, output: _scene(++gen)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pump();
    expect(
      find.bySemanticsLabel('Play'),
      findsOneWidget,
      reason: 'the button kept saying pause after it had already stopped',
    );

    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
}
