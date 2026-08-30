// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import '../benchmark/paint_paths.dart';

void main() {
  testWidgets('a viewport change repaints without rebuilding any widget', (
    tester,
  ) async {
    final stats = PaintStats();
    final scene = CanvasScene()..add(0, 0, 100, 100);
    await tester.pumpWidget(RepaintOnlyCanvas(scene: scene, stats: stats));
    await tester.pump();

    stats.reset();
    for (var i = 0; i < 20; i++) {
      scene.setViewport(i.toDouble(), 0, i + 2560, 1440);
      await tester.pump();
    }

    expect(stats.builds, 0, reason: 'the render loop must not rebuild widgets');
    expect(stats.paints, 20);
  });

  testWidgets('the naive provider path rebuilds once per update', (
    tester,
  ) async {
    final stats = PaintStats();
    final counter = StateProvider<int>((ref) => 0);
    await tester.pumpWidget(
      ProviderScope(child: RebuildCanvas(counter: counter, stats: stats)),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RebuildCanvas)),
    );

    stats.reset();
    for (var i = 1; i <= 20; i++) {
      container.read(counter.notifier).state = i;
      await tester.pump();
    }

    expect(stats.builds, 20, reason: 'this is the cost the spike rejects');
  });

  test('reset clears the cached cull, not only the grid', () {
    final scene = CanvasScene()..add(0, 0, 100, 100);
    scene.setViewport(-10, -10, 200, 200);
    expect(scene.visible, isNotEmpty);

    scene.reset();
    expect(
      scene.visible,
      isEmpty,
      reason: 'a stale slot cached from before the reset is no longer a valid '
          'index into anything the document holds',
    );
  });

  test('the published package never imports Riverpod', () {
    for (final file in _libSources()) {
      expect(
        _directivesOf(file),
        isNot(contains(contains('riverpod'))),
        reason: '${file.path} would put Riverpod back in the render loop',
      );
    }
  });

  test('the spatial index stays free of dart:ui so it can be benchmarked', () {
    final directives = _directivesOf(
      File('${_packageRoot().path}/lib/src/spatial_grid.dart'),
    );
    expect(directives, isNot(contains(contains('dart:ui'))));
    expect(directives, isNot(contains(contains('package:flutter/'))));
  });
}

/// Import and export lines only, so a doc comment naming a package it avoids
/// does not read as a dependency on it.
List<String> _directivesOf(File file) => file
    .readAsLinesSync()
    .map((line) => line.trim())
    .where((line) => line.startsWith('import ') || line.startsWith('export '))
    .toList();

List<File> _libSources() => Directory('${_packageRoot().path}/lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Walks up from the test's working directory so the suite passes whether it
/// is run from the package or from the workspace root.
Directory _packageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File('${dir.path}/lib/voice_canvas.dart').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  throw StateError('could not locate the voice_canvas package root');
}
