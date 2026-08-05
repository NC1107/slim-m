// SPDX-License-Identifier: Apache-2.0
/// The seven synthesised notification sounds (`assets/audio/notifications/`,
/// see that directory's own `sounds.py` for what each one is for) and the
/// seam a fake stands in for, so nothing that plays one ever touches real
/// audio hardware in a test.
///
/// `audioplayers` is the platform layer: the one Flutter audio package that
/// is cross-platform including Linux desktop (its own `audioplayers_linux`
/// plugin wraps GStreamer, a system library, rather than a bundled native
/// compile - the segfault-on-Wayland trap this project already hit was a
/// bundled FFI capturer, not a system-library plugin like this one) and lets
/// a caller name the iOS audio session category directly, which is what
/// keeps a chime from ever taking the session a live call already holds.
/// See docs/dependencies.md for the alternatives this was weighed against.
library;

import 'package:audioplayers/audioplayers.dart';

/// Which chime to play.
enum NotificationSound {
  directMessage('direct_message'),
  mention('mention'),
  groupMessage('group_message'),
  callRing('call_ring'),
  memberJoin('member_join'),
  memberLeave('member_leave'),
  error('error');

  const NotificationSound(this._fileName);
  final String _fileName;

  /// The `rootBundle` key every asset resolves to, matching `pubspec.yaml`'s
  /// declared entries exactly - what `notification_sound_bundle_test.dart`
  /// loads directly to prove the file is really bundled.
  String get assetKey => 'assets/audio/notifications/$_fileName.wav';

  /// What `audioplayers`' `AssetSource` takes: its `AudioCache` prepends
  /// `assets/` itself (confirmed by reading `audio_cache.dart`), so passing
  /// the full [assetKey] here would look up `assets/assets/audio/...` and
  /// find nothing.
  String get _playerPath => 'audio/notifications/$_fileName.wav';
}

/// The seam a test fakes instead of touching a real audio device.
abstract class SoundPlayer {
  Future<void> play(NotificationSound sound);
  Future<void> dispose();
}

/// Plays over `audioplayers`, configured so a chime can never take the
/// session, route, or focus a live call already holds - see the library
/// doc comment above for why that is this package's whole reason to exist.
class AudioPlayersSoundPlayer implements SoundPlayer {
  AudioPlayersSoundPlayer() : _player = AudioPlayer();

  final AudioPlayer _player;

  /// iOS `.ambient`: the platform's own category for a short sound that must
  /// never interrupt or duck whatever else is playing, which is why it is
  /// used here rather than `.playback` with `mixWithOthers` added by hand -
  /// `AudioContextIOS`'s own asserts (read from source, not assumed) refuse
  /// `mixWithOthers` as an explicit option on `.ambient` because the category
  /// already implies it. Android asks for no audio focus at all
  /// (`AndroidAudioFocus.none`), the closest equivalent: a player that never
  /// contends for focus can never be the reason a call's audio pauses.
  static final _context = AudioContext(
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.notificationEvent,
      audioFocus: AndroidAudioFocus.none,
    ),
  );

  @override
  Future<void> play(NotificationSound sound) async {
    // Stopped first, or two overlapping `play()` calls would race.
    await _player.stop();
    await _player.play(AssetSource(sound._playerPath), ctx: _context);
  }

  @override
  Future<void> dispose() => _player.dispose();
}
