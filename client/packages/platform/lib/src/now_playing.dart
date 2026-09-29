// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// What this device is playing right now, for rich presence (decision 0044).
///
/// Only Linux has a source today (MPRIS over D-Bus). Everywhere else
/// [createNowPlayingSource] is null: web has no such API and the other
/// desktops each need their own binding, filed as separate cards.
library;

import 'now_playing_stub.dart' if (dart.library.io) 'now_playing_mpris.dart'
    as impl;

/// One track a local player reports as playing.
class NowPlaying {
  const NowPlaying({required this.title, this.artist});

  final String title;
  final String? artist;

  @override
  bool operator ==(Object other) =>
      other is NowPlaying && other.title == title && other.artist == artist;

  @override
  int get hashCode => Object.hash(title, artist);
}

/// A local player's playback state.
///
/// Listening starts the source (a D-Bus connection, say) and cancelling stops
/// it, so a source nobody listens to costs and reads nothing. Emits null when
/// nothing is playing, and only on change.
abstract interface class NowPlayingSource {
  Stream<NowPlaying?> watch();
}

/// The source for this platform, or null when there is none.
NowPlayingSource? createNowPlayingSource() => impl.createNowPlayingSource();
