// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Ringing the other side of a DM call, and reacting to an incoming ring,
/// an answer, a decline, or a timeout.
///
/// Three choices this feature makes, stated here rather than left implicit:
///
/// - **The ring timeout is entirely server-owned** (`voice::ring::RING_TIMEOUT`
///   in `crates/slimm-server`, 30 seconds today). This controller never runs
///   its own client-side timer; it only reacts to the `call.ring_ended` frame
///   the server publishes once its own timeout fires, so the caller's own
///   call is torn down by the same authority that decided the ring was over,
///   never by a client clock that could drift from it.
/// - **A missed or declined call leaves no trace in the conversation.**
///   No system message is written, so this feature needed no migration and
///   adds no new moderation surface; a transcript of who called whom is a
///   deliberate absence, not an oversight.
/// - **Ringing is not gated on quiet hours**, and follows the account's own
///   notification preference the same way an ordinary DM message already
///   does: a `nothing` preference silences it, `mentions`/`everything` both
///   let it through, since a DM already counts as addressed to that account
///   either way. See `push::call_ring`'s own module doc on the server for
///   why quiet hours structurally cannot narrow that further.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'live_events.dart';
import 'providers.dart';
import 'voice_controller.dart';

/// An incoming ring this account has not yet answered or declined.
class IncomingDmCallRing {
  const IncomingDmCallRing({
    required this.channelId,
    required this.ringId,
    required this.callerId,
  });

  final String channelId;
  final String ringId;
  final String callerId;
}

/// An outgoing ring this account started, waiting on the other side to
/// answer, decline, or let it time out.
class OutgoingDmCallRing {
  const OutgoingDmCallRing({required this.channelId, required this.ringId});

  final String channelId;
  final String ringId;
}

class DmCallRingState {
  const DmCallRingState({this.incoming, this.outgoing});

  final IncomingDmCallRing? incoming;
  final OutgoingDmCallRing? outgoing;

  DmCallRingState copyWith({
    IncomingDmCallRing? incoming,
    bool clearIncoming = false,
    OutgoingDmCallRing? outgoing,
    bool clearOutgoing = false,
  }) => DmCallRingState(
    incoming: clearIncoming ? null : (incoming ?? this.incoming),
    outgoing: clearOutgoing ? null : (outgoing ?? this.outgoing),
  );
}

class DmCallRingController extends StateNotifier<DmCallRingState> {
  DmCallRingController(this._ref) : super(const DmCallRingState()) {
    _sub = _ref.read(liveEventsProvider).listen(_onEvent);
  }

  final Ref _ref;
  late final StreamSubscription<api.ServerEvent> _sub;

  /// A DM's two participants are the whole audience for its own
  /// `call.ringing`/`call.ring_ended` frames, so the caller's own client
  /// receives both events too; [_onEvent] tells its own ring apart from an
  /// incoming one by comparing `callerId` against this session's own id.
  void _onEvent(api.ServerEvent event) {
    switch (event) {
      case api.CallRinging(:final channelId, :final ringId, :final callerId):
        // Own ring already known from starting it; see this method's own doc.
        final selfId = _ref.read(apiProvider).session.tokens?.userId;
        if (callerId == selfId) return;
        state = state.copyWith(
          incoming: IncomingDmCallRing(
            channelId: channelId,
            ringId: ringId,
            callerId: callerId,
          ),
        );
      case api.CallRingEnded(:final ringId, :final outcome):
        _onRingEnded(ringId, outcome);
      default:
        break;
    }
  }

  /// Clears whichever local ring state [ringId] belongs to. For an outgoing
  /// ring that ended in [api.CallRingOutcome.declined] or
  /// [api.CallRingOutcome.timedOut] - the two outcomes where the callee
  /// never joins - this also hangs up the caller's own call, already
  /// connected while it rang (`dm_call_button.dart`), rather than leaving it
  /// running alone: exactly the resource-waste problem this feature exists
  /// to close. [api.CallRingOutcome.answered] and
  /// [api.CallRingOutcome.canceled] need nothing further here.
  void _onRingEnded(String ringId, api.CallRingOutcome outcome) {
    if (state.incoming?.ringId == ringId) {
      state = state.copyWith(clearIncoming: true);
    }
    final outgoing = state.outgoing;
    if (outgoing != null && outgoing.ringId == ringId) {
      state = state.copyWith(clearOutgoing: true);
      final shouldHangUp =
          outcome == api.CallRingOutcome.declined ||
          outcome == api.CallRingOutcome.timedOut;
      if (shouldHangUp) _hangUpIfStillOn(outgoing.channelId);
    }
  }

  void _hangUpIfStillOn(String channelId) {
    final voice = _ref.read(voiceControllerProvider);
    if (voice.channelId == channelId) {
      unawaited(_ref.read(voiceControllerProvider.notifier).leave());
    }
  }

  /// Starts ringing the other side of [channelId]'s call.
  ///
  /// Best-effort: a failure here means the callee's device is never told,
  /// but the caller's own call - already joined by the time this runs, see
  /// `dm_call_button.dart` - proceeds regardless, exactly as every call did
  /// before ringing existed. There is nothing durable to retry, and no
  /// persistent error state worth surfacing for a signal this transient.
  Future<void> startOutgoingRing(String channelId) async {
    try {
      final started = await _ref.read(apiProvider).ringDmCall(channelId);
      state = state.copyWith(
        outgoing: OutgoingDmCallRing(
          channelId: channelId,
          ringId: started.ringId,
        ),
      );
    } on api.ApiException {
      // Best-effort; see this method's own doc.
    }
  }

  /// Clears the incoming ring without declining it - the accept path, whose
  /// actual "answer" is the callee's own call join a moment later (a
  /// heartbeat is what the server treats as answering; see `voice/ring.rs`'s
  /// own doc for why there is no separate accept route to call here).
  void dismissIncoming() {
    if (mounted) state = state.copyWith(clearIncoming: true);
  }

  /// Declines an incoming ring.
  Future<void> decline(IncomingDmCallRing ring) async {
    dismissIncoming();
    try {
      await _ref.read(apiProvider).declineDmCallRing(ring.channelId);
    } on api.ApiException {
      // Best-effort: this ring times out on the caller's own side regardless.
    }
  }

  /// Forgets any ring state a dropped connection could otherwise leave stuck
  /// forever (an incoming banner nobody can answer, or a caller waiting on a
  /// `call.ring_ended` that will never arrive). [SyncController.start] calls
  /// this on every (re)connect, `DmCallActivityController.clear`'s own shape.
  void clear() {
    if (mounted) state = const DmCallRingState();
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}

final dmCallRingControllerProvider =
    StateNotifierProvider<DmCallRingController, DmCallRingState>(
      (ref) => DmCallRingController(ref),
    );
