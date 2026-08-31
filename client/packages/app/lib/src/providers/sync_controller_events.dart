// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// [SyncController]'s event-application half: how one frame off the
/// socket becomes local state.
///
/// Split out of `sync_controller.dart`, which had reached the 500-line
/// hard ceiling with no headroom left - any change to it, including a
/// two-line bug fix, broke the file budget. The seam is real rather than
/// arbitrary: everything here decides what a received event MEANS, while
/// what remains owns the connection and session lifecycle that delivers
/// one. A `part` rather than a separate class because these methods are
/// private to [SyncController] and reach its generation guard.
part of 'sync_controller.dart';

extension SyncControllerEvents on SyncController {
  /// How one frame from the socket changes local state. A method of its own
  /// so [applyServerEventForTest] can drive it without a real socket.
  Future<void> _applyServerEvent(
    int generation,
    SlimmApi api,
    MessageStore store,
    ServerEvent event,
  ) async {
    bool isCurrent() => generation == _generation;
    switch (event) {
      case MessageCreated(:final message):
        // A DM's first message is a channel never fetched; materialise it first or this no-ops.
        if (!await store.hasChannel(message.channelId)) {
          await _channelRefresher.refreshOnce(api, store, isCurrent: isCurrent);
        }
        if (!isCurrent()) return;
        await store.applyMessage(message);
      case MessageEdited(:final message, :final opSeq):
        if (!await store.hasChannel(message.channelId)) {
          await _channelRefresher.refreshOnce(api, store, isCurrent: isCurrent);
        }
        if (!isCurrent()) return;
        if (!await _placeLiveOp(message.channelId, opSeq, store)) return;
        await store.applyMessage(message);
      case MessageDeleted(:final channelId, :final messageId, :final opSeq):

        /// Closes a real gap: this switch previously had no case for a
        /// delete at all, so a message removed by another user (or this
        /// account's own delete looping back) never left the local store
        /// and stayed visible until the next full resync.
        if (!await _placeLiveOp(channelId, opSeq, store)) return;
        await store.discard(messageId);
      case ChannelCreated(:final channel):
      case ChannelUpdated(:final channel):
        await store.upsertChannels([channel]);
      case ChannelDeleted(:final channelId):
        // A channel already known to be gone; no round trip needed for that.
        await store.removeChannel(channelId);
      case OverwriteChanged():
      case RoleChanged():
      case MemberRoleChanged():
      case CategoryChanged():
        // None say which channel (or category) changed; a refresh finds it.
        await _channelRefresher.refreshOnce(api, store, isCurrent: isCurrent);
      case ErrorEvent(:final needsResync) when needsResync:
        // The server closed a connection that fell behind; a restart re-runs catch-up.
        unawaited(start());
      case _:
        break;
    }
  }

  /// Decides whether a live op may be applied, and advances the cursor when
  /// it may. Answers false when the caller must not apply the payload.
  ///
  /// A gap schedules one reconcile rather than applying an op it cannot place:
  /// moving the cursor past something never seen would strand it permanently,
  /// where a stall only lasts until the next round.
  Future<bool> _placeLiveOp(
    String channelId,
    int? opSeq,
    MessageStore store,
  ) async {
    final cursor = await store.opCursorFor(channelId);
    switch (liveOpDecision(opSeq, cursor)) {
      case LiveOpOutcome.ignored:
        return false;
      case LiveOpOutcome.needsReconcile:
        unawaited(reconcile().catchError((_) {}));
        return false;
      case LiveOpOutcome.applied:
        if (opSeq != null) await store.setOpCursor(channelId, opSeq);
        return true;
    }
  }
}
