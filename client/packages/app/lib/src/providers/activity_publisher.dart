// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Tells the server what this device is playing, and only when the person has
/// switched that on (decision 0044).
///
/// Three things must all hold before anything leaves the device: the source
/// is enabled, the caller has not chosen to appear offline, and a player is
/// actually playing. The source itself is not even started while the setting
/// is off, so an opted-out device never reads a player. The server applies
/// the same hidden rule to every viewer; the check here is a second lock, not
/// the only one.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_platform/platform.dart';

import 'activity_sharing_settings.dart';
import 'live_events.dart';
import 'presence_controller.dart';
import 'providers.dart';

/// The platform's now-playing source, or null where there is none. Overridden
/// in tests with a fake.
final nowPlayingSourceProvider = Provider<NowPlayingSource?>(
  (ref) => createNowPlayingSource(),
);

/// A track as the wire carries it, cut to the server's cap so a long title is
/// shortened here rather than refused there.
api.PresenceActivity activityFromNowPlaying(NowPlaying playing) {
  String cap(String text) =>
      String.fromCharCodes(text.runes.take(api.PresenceActivity.maxTextChars));
  final artist = playing.artist;
  return api.PresenceActivity(
    kind: api.ActivityKind.listening,
    title: cap(playing.title),
    subtitle: artist == null ? null : cap(artist),
  );
}

class ActivityPublisher {
  ActivityPublisher(this._ref) {
    _ref.onDispose(_stop);
    _ref.listen<bool>(
      shareListeningProvider,
      (_, enabled) => _onEnabled(enabled),
      fireImmediately: true,
    );
    _ref.listen<api.PresenceVisibility?>(
      presenceVisibilityDisplayProvider,
      (_, _) => unawaited(_push()),
    );
    _events = _ref.read(liveEventsProvider).listen(_onEvent);
  }

  final Ref _ref;
  late final StreamSubscription<api.ServerEvent> _events;
  StreamSubscription<NowPlaying?>? _source;
  NowPlaying? _playing;
  api.PresenceActivity? _sent;

  bool get _hidden =>
      _ref.read(presenceVisibilityDisplayProvider) ==
      api.PresenceVisibility.hidden;

  void _onEnabled(bool enabled) {
    if (enabled) {
      _source ??= _ref
          .read(nowPlayingSourceProvider)
          ?.watch()
          .listen(_onPlaying);
    } else {
      unawaited(_source?.cancel());
      _source = null;
      _playing = null;
    }
    unawaited(_push());
  }

  void _onPlaying(NowPlaying? playing) {
    _playing = playing;
    unawaited(_push());
  }

  /// A reconnect drops the server's copy; our own presence frame arriving
  /// without an activity while we hold one is how that shows up.
  void _onEvent(api.ServerEvent event) {
    if (event is! api.PresenceChanged || event.activity != null) return;
    if (event.userId != _ref.read(sessionProvider).tokens?.userId) return;
    if (_sent == null) return;
    _sent = null;
    unawaited(_push());
  }

  Future<void> _push() async {
    final playing = _playing;
    final wanted =
        _ref.read(shareListeningProvider) && !_hidden && playing != null
        ? activityFromNowPlaying(playing)
        : null;
    if (wanted == _sent) return;
    final client = _ref.read(apiProvider);
    final previous = _sent;
    _sent = wanted;
    try {
      if (wanted == null) {
        await client.clearPresenceActivity();
      } else {
        await client.setPresenceActivity(wanted);
      }
    } on api.ApiException {
      // Retried by the next change; the server forgets it with the socket anyway.
      _sent = previous;
    }
  }

  void _stop() {
    unawaited(_events.cancel());
    unawaited(_source?.cancel());
  }
}

/// Watched from the signed-in shell so it lives for the session, the same
/// forced-instantiation shape the sound controller uses.
final activityPublisherProvider = Provider<ActivityPublisher>(
  (ref) => ActivityPublisher(ref),
);
