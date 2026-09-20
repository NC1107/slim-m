// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
part of 'voice_controller.dart';

/// Deciding whether a drop is worth rejoining, and driving the attempts.
///
/// Split out for [VoiceController]'s own 500-line hard ceiling, as a mixin
/// for the reason [VoiceControllerInputMixin] gives. The timer itself lives
/// in [VoiceAutoRejoin]; this is the part that knows what a drop meant and
/// what to do about it.
mixin VoiceControllerRejoinMixin on StateNotifier<VoiceState> {
  /// Bridges to [VoiceController]'s own members, [VoiceControllerInputMixin]'s
  /// own reasoning: the `on` clause, not this file's privacy, is what bounds
  /// what a mixin can reach.
  VoiceAutoRejoin get _rejoinAttempts;
  Future<void> join(String channelId);

  /// Which SFU-decided drops are an accident rather than a decision.
  ///
  /// Only a lost connection. [VoiceDisconnect.replacedByOtherDevice] means
  /// this same account answered somewhere else, and rejoining would have two
  /// devices of one person fighting over the room. [VoiceDisconnect.removed]
  /// means the server took this participant out, which is an answer, not a
  /// question. Rejoining either would be overriding somebody.
  static bool _rejoinableDrop(VoiceDisconnect dropped) =>
      dropped == VoiceDisconnect.connectionLost;

  /// Queues the next attempt and records whether there was one to queue, so
  /// [VoiceState.rejoining] is true exactly while an attempt is pending or in
  /// flight and false the moment the budget runs out - which is when the
  /// manual "Try again" becomes the honest thing to show.
  void _scheduleAutoRejoin(String channelId) {
    final queued = _rejoinAttempts.schedule(
      () => unawaited(_attemptAutoRejoin(channelId)),
    );
    state = state.copyWith(rejoining: queued);
  }

  /// One attempt, and the decision about the next one.
  ///
  /// Chained from its own outcome rather than from the session's state
  /// stream, because the common failure here never reaches that stream: with
  /// the network still down, [join] fails on the `/voice/token` request and
  /// sets [VoiceSessionState.failed] itself, without the SFU ever having been
  /// contacted to drop us.
  Future<void> _attemptAutoRejoin(String channelId) async {
    // A hang-up or another channel already moved on; this attempt is not about that call.
    if (state.channelId != channelId) return;
    await join(channelId);
    if (state.channelId != channelId) return;
    if (state.state == VoiceSessionState.connected) return;
    _scheduleAutoRejoin(channelId);
  }
}
