// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Unsent composer text, held per channel for as long as the session lasts.
///
/// `ChannelScreen` reuses its own `State` across a channel switch in the
/// common case (see `channel_read_marker.dart`'s doc comment), which is why a
/// draft looked like it should already survive one and did not: nothing ever
/// told the shared `TextEditingController` which channel its text belonged
/// to, so switching channels either carried the words into the wrong one or,
/// wherever `ConversationPane` happens to tear the screen down instead (a
/// detour through voice, a DM call, or the canvas), lost them outright.
///
/// This is the fix: text is saved against the channel it was typed in and
/// restored against whichever channel is open now, independent of whether
/// the widget underneath survived.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'providers.dart';

/// Holds every channel's unsent composer text, in memory only.
///
/// In-memory for the session rather than written to the shared drift
/// database: it covers exactly the reported loss (switch channels, come
/// back, the words are still there) with no migration and no new place a
/// sign-out has to remember to wipe. The cost is that a restart loses every
/// draft, accepted because the report was about switching channels, never
/// about restarting the app.
///
/// A reply-in-progress and a staged attachment are deliberately not held
/// here, and that is a decision, not an oversight: `ChannelScreen` already
/// clears the reply target on a channel switch (see its own `didUpdateWidget`
/// doc comment, "a reply is scoped to the conversation it was started in"),
/// and `Composer` now clears a staged attachment the same way. Restoring text
/// while a stale reply or attachment silently rode along pointed at the
/// channel it came from would be worse than restoring nothing.
class ChannelDraftsController {
  ChannelDraftsController(this._ref) {
    _account = _ref.read(sessionProvider).tokens?.userId;
    _sub = _ref.read(sessionProvider).changes.listen(_onSessionChanged);
  }

  final Ref _ref;
  final Map<String, String> _drafts = {};
  late final StreamSubscription<api.TokenPair?> _sub;
  String? _account;

  /// Whatever was last saved for [channelId], or an empty string if there is
  /// nothing to restore.
  String draftFor(String channelId) => _drafts[channelId] ?? '';

  /// Saves [text] as [channelId]'s draft, or forgets it once it is empty: an
  /// empty draft and no draft have to read the same way, or every channel a
  /// member ever opens and leaves empty grows the map forever.
  void save(String channelId, String text) {
    if (text.isEmpty) {
      _drafts.remove(channelId);
    } else {
      _drafts[channelId] = text;
    }
  }

  /// Forgets [channelId]'s draft outright, called once its text has been
  /// sent rather than left to [save] with an empty string a rebuild later.
  void clear(String channelId) => _drafts.remove(channelId);

  /// Sign-out, or a different account signing in on this process, empties
  /// every draft: the same account-boundary rule `BlocksController` already
  /// follows, because Riverpod's container outlives a sign-out and the next
  /// account on this device must never read the last one's unfinished words.
  void _onSessionChanged(api.TokenPair? tokens) {
    if (tokens == null) {
      _account = null;
      _drafts.clear();
      return;
    }
    if (tokens.userId == _account) return;
    _account = tokens.userId;
    _drafts.clear();
  }

  void dispose() => unawaited(_sub.cancel());
}

/// Deliberately not `autoDispose`: a draft has to survive for as long as the
/// session does, independent of whether any particular `ChannelScreen` is
/// currently mounted to read or write one.
final channelDraftsProvider = Provider<ChannelDraftsController>((ref) {
  final controller = ChannelDraftsController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});
