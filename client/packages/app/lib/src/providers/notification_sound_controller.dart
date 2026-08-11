// SPDX-License-Identifier: Apache-2.0
/// Plays a notification chime for the three kinds of event this client can
/// already see live: an incoming message, a voice roster changing while
/// connected, and a DM call becoming active while this device is not
/// already on it.
///
/// Wired at `HomeShell` (`ref.watch`, the same forced-instantiation shape
/// [blocksProvider] already uses) so it is created once for the signed-in
/// session rather than only while some particular screen happens to be
/// mounted, and torn down with the container rather than with any one route.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_rtc/rtc.dart';

import '../audio/notification_sound.dart';
import '../widgets/message_mentions.dart' show messageMentionsUsername;
import 'blocks_controller.dart';
import 'dm_call_activity.dart';
import 'live_events.dart';
import 'notification_sound_rules.dart';
import 'notification_sound_settings.dart';
import 'providers.dart';
import 'voice_controller.dart';
import 'voice_settings_controller.dart' show voiceSettingsControllerProvider;

class NotificationSoundController {
  NotificationSoundController(this._ref, {SoundPlayer? player})
    : _player = player ?? AudioPlayersSoundPlayer() {
    _messages = _ref.read(liveEventsProvider).listen(_onServerEvent);
    _voiceSub = _ref.listen<VoiceState>(
      voiceControllerProvider,
      _onVoiceStateChanged,
    );
    _dmCallSub = _ref.listen<Map<String, bool>>(
      dmCallActivityProvider,
      _onDmCallActivityChanged,
    );
  }

  final Ref _ref;
  final SoundPlayer _player;
  late final StreamSubscription<api.ServerEvent> _messages;
  late final ProviderSubscription<VoiceState> _voiceSub;
  late final ProviderSubscription<Map<String, bool>> _dmCallSub;

  /// Who was already in the call the moment [voiceControllerProvider] last
  /// read [VoiceSessionState.connected], excluding this device's own
  /// identity - null whenever not connected. See [diffRoster]'s own doc
  /// comment for why null is what keeps the room's existing occupants from
  /// reading as a burst of live joins the moment this device arrives.
  Set<String>? _rosterBaseline;

  /// Cached against the id it was resolved for, so a different account
  /// signing in on the same device (the local store is one file for the
  /// whole app, per `SyncController`'s own doc comment) never reuses a
  /// stale username to decide a mention.
  String? _selfUsername;
  String? _selfUsernameForId;

  // --- Messages ---

  void _onServerEvent(api.ServerEvent event) {
    if (event case api.MessageCreated(:final message)) {
      unawaited(_onMessageCreated(message));
    }
  }

  Future<void> _onMessageCreated(api.Message message) async {
    if (!_ref.read(messageSoundSettingsProvider)) return;
    final client = _ref.read(apiProvider);
    final selfId = client.session.tokens?.userId;
    if (!messageEarnsASound(
      authorId: message.authorId,
      selfId: selfId,
      authorBlocked: _ref.read(blocksProvider).contains(message.authorId),
    )) {
      return;
    }

    final store = await _ref.read(storeProvider.future);
    final channel = await store.watchChannelRow(message.channelId).first;
    final isDm = channel?.kind == 'dm';

    var mentionsSelf = false;
    if (!isDm && selfId != null) {
      final username = await _resolveSelfUsername(selfId);
      if (username != null) {
        mentionsSelf = messageMentionsUsername(message.content, username);
      }
    }

    await _player.play(
      messageSoundKind(isDm: isDm, mentionsSelf: mentionsSelf),
    );
  }

  /// Best-effort: a lookup failure just leaves a group message read as an
  /// ordinary one rather than a mention this one time, and the next message
  /// that needs it tries again rather than caching a failure forever.
  Future<String?> _resolveSelfUsername(String selfId) async {
    if (_selfUsernameForId == selfId) return _selfUsername;
    try {
      final me = await _ref.read(apiProvider).me();
      _selfUsername = me.username;
      _selfUsernameForId = selfId;
    } catch (_) {
      // Handled above: the caller reads the unchanged (possibly null) cache.
    }
    return _selfUsername;
  }

  // --- Voice roster (member join/leave) and call failures (error) ---

  void _onVoiceStateChanged(VoiceState? previous, VoiceState next) {
    _handleVoiceError(previous, next);
    _handleRosterChange(previous, next);
  }

  void _handleVoiceError(VoiceState? previous, VoiceState next) {
    if (next.error == null || next.error == previous?.error) return;
    if (!_ref.read(messageSoundSettingsProvider)) return;
    unawaited(_player.play(NotificationSound.error));
  }

  /// [VoiceController] fans `states` and `participantChanges` in from two
  /// independent streams, so the event that flips [VoiceState.state] to
  /// [VoiceSessionState.connected] carries whatever stale `participants`
  /// list preceded it - the real roster arrives moments later on the other
  /// stream. Treating that first, empty-or-stale reading as the baseline
  /// would let the real roster, arriving right after it, read as a burst of
  /// live joins for everyone already in the room. [identical] below is what
  /// tells the two apart: the stale reading carries the exact same list
  /// instance, since nothing copied a new one into it.
  void _handleRosterChange(VoiceState? previous, VoiceState next) {
    if (next.state != VoiceSessionState.connected) {
      _rosterBaseline = null;
      return;
    }
    if (identical(next.participants, previous?.participants)) return;
    final selfId = _ref.read(apiProvider).session.tokens?.userId;
    final current = {
      for (final p in next.participants)
        if (p.identity != selfId) p.identity,
    };
    final diff = diffRoster(_rosterBaseline, current);
    _rosterBaseline = diff.baseline;
    if (diff.joined.isEmpty && diff.left.isEmpty) return;
    if (!_ref.read(voiceSettingsControllerProvider).joinLeaveSoundsEnabled) {
      return;
    }
    // +1 for this device's own presence, excluded from `current` above.
    if (current.length + 1 > soundsDisabledAboveParticipants) return;
    if (diff.joined.isNotEmpty) {
      unawaited(_player.play(NotificationSound.memberJoin));
    }
    if (diff.left.isNotEmpty) {
      unawaited(_player.play(NotificationSound.memberLeave));
    }
  }

  // --- An incoming DM call ---

  void _onDmCallActivityChanged(
    Map<String, bool>? previous,
    Map<String, bool> next,
  ) {
    if (!_ref.read(voiceSettingsControllerProvider).callRingSoundEnabled) {
      return;
    }
    final myCallChannel = _ref.read(voiceControllerProvider).channelId;
    for (final entry in next.entries) {
      // No prior answer here is a catch-up resolution, not a live start; see [diffRoster].
      if (previous == null || !previous.containsKey(entry.key)) continue;
      final wasActive = previous[entry.key] ?? false;
      if (entry.value && !wasActive && entry.key != myCallChannel) {
        unawaited(_player.play(NotificationSound.callRing));
      }
    }
  }

  void dispose() {
    unawaited(_messages.cancel());
    _voiceSub.close();
    _dmCallSub.close();
    unawaited(_player.dispose());
  }
}

final notificationSoundControllerProvider =
    Provider<NotificationSoundController>((ref) {
      final controller = NotificationSoundController(ref);
      ref.onDispose(controller.dispose);
      return controller;
    });
