// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The rich-presence sources, all behind one seam (decision 0044).
///
/// A feed is a Settings switch plus a stream of what that source sees. The
/// publisher owns the privacy rules (switch on, not hidden, nothing opened
/// otherwise), so a new source only declares itself in [activityFeedsProvider]
/// and never touches them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_platform/platform.dart';

import 'activity_sharing_settings.dart';

/// The platform's now-playing source, or null where there is none. Overridden
/// in tests with a fake.
final nowPlayingSourceProvider = Provider<NowPlayingSource?>(
  (ref) => createNowPlayingSource(),
);

/// A track as the wire carries it, cut to the server's cap so a long title is
/// shortened here rather than refused there.
api.PresenceActivity activityFromNowPlaying(NowPlaying playing) {
  final artist = playing.artist;
  return api.PresenceActivity(
    kind: api.ActivityKind.listening,
    title: capActivityText(playing.title),
    subtitle: artist == null ? null : capActivityText(artist),
  );
}

/// The platform's game source, or null where there is none. Overridden in
/// tests with a fake.
final gameSourceProvider = Provider<GameSource?>((ref) => createGameSource());

api.PresenceActivity activityFromGame(RunningGame game) => api.PresenceActivity(
  kind: api.ActivityKind.playing,
  title: capActivityText(game.name),
);

String capActivityText(String text) =>
    String.fromCharCodes(text.runes.take(api.PresenceActivity.maxTextChars));

class ActivityFeed {
  const ActivityFeed({
    required this.label,
    required this.description,
    required this.enabled,
    required this.available,
    required this.open,
  });

  /// The switch's label and the sentence saying what turning it on reads.
  final String label;
  final String description;

  /// The persisted switch; off until the person turns it on.
  final StateNotifierProvider<ActivitySwitchController, bool> enabled;

  /// False where this device has no such source, so Settings omits the row.
  final ProviderListenable<bool> available;

  /// Starts reading. Called only while enabled and visible, and the returned
  /// stream is cancelled the moment either stops being true.
  final Stream<api.PresenceActivity?> Function(Ref ref) open;
}

final _listeningFeed = ActivityFeed(
  label: 'Show what I am listening to',
  description:
      'Reads the track from any player on this computer and shows it on '
      'your profile card and member row. It clears when you pause, stop or '
      'quit.',
  enabled: shareListeningProvider,
  available: nowPlayingSourceProvider.select((source) => source != null),
  open: (ref) => ref
      .read(nowPlayingSourceProvider)!
      .watch()
      .map(
        (playing) => playing == null ? null : activityFromNowPlaying(playing),
      ),
);

final _gameFeed = ActivityFeed(
  label: 'Show the game I am playing',
  description:
      'Checks what is running against the list of games below and nothing '
      'else. A program that is not on the list is never reported, stored or '
      'logged. It clears when the game quits.',
  enabled: shareGameProvider,
  available: gameSourceProvider.select((source) => source != null),
  open: (ref) => ref
      .read(gameSourceProvider)!
      .watch()
      .map((game) => game == null ? null : activityFromGame(game)),
);

/// In priority order: when two sources both report something, the first
/// one is what others see.
final activityFeedsProvider = Provider<List<ActivityFeed>>(
  (ref) => [_listeningFeed, _gameFeed],
);

/// Feeds this device can actually run, for Settings.
final availableActivityFeedsProvider = Provider<List<ActivityFeed>>((ref) {
  return [
    for (final feed in ref.watch(activityFeedsProvider))
      if (ref.watch(feed.available)) feed,
  ];
});

/// What the server last accepted as this device's activity, so Settings can
/// show exactly what others can read. Null when nothing is shared.
final sharedActivityProvider = StateProvider<api.PresenceActivity?>(
  (ref) => null,
);
