// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Local-only looping hold music for a call you are alone in.
///
/// The loop is synthesised from `scene_synth.dart`'s bell voice at play time,
/// so no third-party audio ships and there is no licence to track. It goes to
/// this device's own player and is never published to the room.
library;

import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_sound.dart' show AudioPlayersSoundPlayer;
import 'scene_synth.dart' as scene_synth;

abstract class HoldMusicPlayer {
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

/// C major pentatonic, one soft bell every two seconds; the last one rings
/// out to the loop point so the repeat has no click.
const _pentatonic = [
  261.63,
  329.63,
  392.0,
  440.0,
  523.25,
  440.0,
  392.0,
  329.63,
];
const _noteGap = 2.0;
const _noteLength = 2.4;

/// Quieter than a chime: this runs for minutes, not a moment.
const holdMusicVolume = 0.2;

Uint8List _render(Object? _) => renderHoldLoop();

Uint8List renderHoldLoop() {
  final notes = [
    for (var i = 0; i < _pentatonic.length; i++)
      scene_synth.SynthNote(
        frequency: _pentatonic[i],
        start: i * _noteGap,
        seconds: _noteLength,
      ),
  ];
  return scene_synth.encodeWav16(scene_synth.render(notes, tail: 0));
}

class AudioPlayersHoldMusicPlayer implements HoldMusicPlayer {
  /// Built on first use, so a session that never enables hold music never touches the audio plugin.
  AudioPlayer? _created;
  AudioPlayer get _player => _created ??= AudioPlayer();
  Uint8List? _wav;

  @override
  Future<void> start() async {
    final wav = _wav ?? await compute<Object?, Uint8List>(_render, null);
    _wav = wav;
    await _player.stop();
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(
      BytesSource(wav, mimeType: 'audio/wav'),
      volume: holdMusicVolume,
      ctx: AudioPlayersSoundPlayer.sharedAmbientContext,
    );
  }

  @override
  Future<void> stop() async => _created?.stop();

  @override
  Future<void> dispose() async => _created?.dispose();
}

final holdMusicPlayerProvider = Provider<HoldMusicPlayer>((ref) {
  final player = AudioPlayersHoldMusicPlayer();
  ref.onDispose(player.dispose);
  return player;
});
