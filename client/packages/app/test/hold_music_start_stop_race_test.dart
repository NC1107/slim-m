// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A stop that lands while the first loop is still rendering must win.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/audio/hold_music_player.dart';

class _Output implements HoldLoopOutput {
  final calls = <String>[];

  @override
  Future<void> play(Uint8List wav) async => calls.add('play');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> dispose() async {}
}

void main() {
  test('stop during the first render means the loop never starts', () async {
    final render = Completer<Uint8List>();
    final output = _Output();
    final player = AudioPlayersHoldMusicPlayer(
      render: () => render.future,
      output: output,
    );

    final started = player.start();
    await player.stop();
    render.complete(Uint8List(4));
    await started;

    expect(output.calls, isNot(contains('play')));
  });

  test('start after a stop still plays', () async {
    final output = _Output();
    final player = AudioPlayersHoldMusicPlayer(
      render: () async => Uint8List(4),
      output: output,
    );

    await player.start();
    await player.stop();
    await player.start();

    expect(output.calls.where((c) => c == 'play'), hasLength(2));
  });
}
