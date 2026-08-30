// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Phase 5 spike: what routing the canvas hot path through Riverpod costs
/// against a plain [ChangeNotifier] driving the painter directly.
///
/// Hosted by `flutter test` because the honest comparison needs the real
/// `ChangeNotifier`, the real widget pipeline, and real `flutter_riverpod`:
/// `flutter test benchmark/hot_path_benchmark.dart`.
///
/// `flutter test` is a debug JIT build with assertions on, so absolute frame
/// figures here are far above release. Read the deltas and the counts.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'paint_paths.dart';

const int _updates = 600;

void main() {
  testWidgets('dispatch cost per update', (tester) async {
    var sink = 0;
    final bare = _Bare()..addListener(() => sink++);

    final small = CanvasScene()..add(0, 0, 10, 10);
    small.addListener(() => sink++);
    final big = _sceneOf(20000);
    big.addListener(() => sink++);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final counter = StateProvider<int>((ref) => 0);
    container.listen<int>(counter, (prev, next) => sink++);

    final bareNs = _time(bare.ping);
    final riverpodNs = _time(() => container.read(counter.notifier).state++);
    final smallNs = _time(small.recull);
    final bigNs = _time(() => big.setViewport(0, 0, 2560, 1440));

    debugPrint('sink $sink, big scene visible ${big.visible.length}');
    _line('ChangeNotifier notifyListeners', bareNs);
    _line('Riverpod StateProvider dispatch', riverpodNs);
    _line('  ratio', riverpodNs / bareNs, unit: 'x');
    _line('recull + notify, 1 object', smallNs);
    _line('recull + notify, 20000 objects', bigNs);
  });

  testWidgets('frame cost, repaint-only against rebuild', (tester) async {
    final stats = PaintStats();
    final scene = CanvasScene()..add(0, 0, 10, 10);

    await tester.pumpWidget(RepaintOnlyCanvas(scene: scene, stats: stats));
    await tester.pump();
    final floorUs = await _pumps(tester, _updates, () {});

    stats.reset();
    final repaintUs = await _pumps(tester, _updates, () {
      scene.setViewport(0, 0, 2560, 1440);
    });
    final repaintBuilds = stats.builds;
    final repaintPaints = stats.paints;

    stats.reset();
    final counter = StateProvider<int>((ref) => 0);
    await tester.pumpWidget(
      ProviderScope(child: RebuildCanvas(counter: counter, stats: stats)),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RebuildCanvas)),
    );
    stats.reset();
    var i = 0;
    final rebuildUs = await _pumps(tester, _updates, () {
      container.read(counter.notifier).state = ++i;
    });

    _line('pump() harness floor, nothing changing', floorUs, unit: 'us');
    _line('repaint-only path', repaintUs, unit: 'us');
    _line('riverpod rebuild path', rebuildUs, unit: 'us');
    _line('  repaint-only over floor', repaintUs - floorUs, unit: 'us');
    _line('  riverpod over floor', rebuildUs - floorUs, unit: 'us');
    debugPrint('repaint-only builds=$repaintBuilds paints=$repaintPaints');
    debugPrint('riverpod     builds=${stats.builds} paints=${stats.paints}');
  });

  testWidgets('StreamProvider cannot deliver inside the frame', (tester) async {
    final scene = CanvasScene()..add(0, 0, 10, 10);
    var synchronous = 0;
    scene.addListener(() => synchronous++);
    scene.recull();

    final controller = StreamController<int>.broadcast();
    addTearDown(controller.close);
    final container = ProviderContainer(
      overrides: <Override>[
        _viewportStream.overrideWith((ref) => controller.stream),
      ],
    );
    addTearDown(container.dispose);
    var streamed = 0;
    container.listen<AsyncValue<int>>(_viewportStream, (prev, next) {
      if (next.hasValue) {
        streamed++;
      }
    });
    await tester.pump();

    controller.add(1);
    final beforeTurn = streamed;
    await tester.pump();

    debugPrint('ChangeNotifier listeners run in the same call: $synchronous');
    debugPrint('StreamProvider seen before the loop turned: $beforeTurn');
    debugPrint('StreamProvider seen after: $streamed');
  });
}

final _viewportStream = StreamProvider<int>((ref) => const Stream<int>.empty());

class _Bare extends ChangeNotifier {
  void ping() => notifyListeners();
}

CanvasScene _sceneOf(int count) {
  final scene = CanvasScene(capacity: count);
  var x = 0.0;
  var y = 0.0;
  for (var i = 0; i < count; i++) {
    x = (x + 977) % 51200 - 25600;
    y = (y + 613) % 51200 - 25600;
    scene.add(x, y, x + 256, y + 192);
  }
  return scene;
}

Future<double> _pumps(
    WidgetTester tester, int n, void Function() mutate) async {
  final sw = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    mutate();
    await tester.pump();
  }
  sw.stop();
  return sw.elapsedMicroseconds / n;
}

void _line(String label, double value, {String unit = 'ns'}) {
  debugPrint(
      '${label.padRight(38)} ${value.toStringAsFixed(unit == 'ns' ? 0 : 2).padLeft(10)} $unit');
}

/// Adaptive-batch timing, same rules as the spatial-grid harness: warm up,
/// then take the median of several batches rather than one wall-clock read.
double _time(void Function() body) {
  final warm = Stopwatch()..start();
  var ops = 0;
  while (warm.elapsedMicroseconds < 120000) {
    body();
    ops++;
  }
  warm.stop();
  final batch =
      (25000 / (warm.elapsedMicroseconds / ops)).ceil().clamp(1, 1 << 20);

  final samples = <double>[];
  for (var t = 0; t < 9; t++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < batch; i++) {
      body();
    }
    sw.stop();
    samples.add(sw.elapsedMicroseconds * 1000 / batch);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}
