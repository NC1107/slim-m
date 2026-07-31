// SPDX-License-Identifier: Apache-2.0
/// Applying the message op stream: how an edit or a delete made while this
/// client was offline finally reaches it.
///
/// A sibling of `sync_controller.dart` rather than part of it, for the line
/// budget.
///
/// The rules here are conventions with no type behind them, and each is a
/// one-word mistake with no symptom until much later, so each has its own
/// test: an op is applied before its cursor moves, an unknown kind resets
/// rather than being skipped, and a live op is applied only when it is exactly
/// the next one.
library;

import 'package:slimm_api/api.dart';
import 'package:slimm_data/data.dart';

/// What applying a page of ops asks the caller to do next.
enum OpsOutcome {
  /// Everything in the page was understood and applied.
  applied,

  /// The page held a kind this client cannot interpret, so it cannot know what
  /// the op did. Skipping it would advance the cursor past a change that was
  /// never made locally, leaving a stale copy nothing would ever correct, so
  /// the caller resets the channel instead.
  needsReset,
}

/// Applies a page of ops in order and advances the op cursor to the last one
/// actually applied.
///
/// The cursor moves per op rather than once at the end, so an interruption
/// leaves the client asking for exactly what it has not yet seen rather than
/// replaying a page it half-applied. Replaying is harmless (an edit and a
/// delete are both idempotent by message id) but asking again for what is
/// already applied is not free.
Future<OpsOutcome> applyOps(
  MessageStore store,
  String channelId,
  List<MessageOp> ops,
) async {
  for (final op in ops) {
    switch (op) {
      case MessageEditOp(:final content, :final editedAt):
        // Gone or collapsed; a later op is what the client acts on instead.
        if (content != null) {
          await store.applyEdit(op.messageId, content, editedAt);
        }
      case MessageDeleteOp():
        await store.discard(op.messageId);
      case MessageUnknownOp():
        return OpsOutcome.needsReset;
    }
    await store.setOpCursor(channelId, op.seq);
  }
  return OpsOutcome.applied;
}

/// What a live op frame asks the caller to do.
enum LiveOpOutcome {
  /// Already applied, or older than the cursor. Nothing to do.
  ignored,

  /// Exactly the next op: applied and the cursor advanced.
  applied,

  /// A gap, so the payload was deliberately not applied. Reconcile instead.
  needsReconcile,
}

/// Decides what to do with one live op, by the `+1` adjacency test.
///
/// Identical in shape to `CanvasSync.applyLive`, and it should read as
/// identical, because a reader who has learned one should recognise the other.
///
/// A frame arriving out of order is the reason this exists: delivery order
/// across concurrent writers is best-effort, so an op two ahead of the cursor
/// means something in between has not been seen, and applying it anyway would
/// move the cursor past that gap forever.
///
/// A null [opSeq] is an old server with no op stream. The frame is applied the
/// way it always was and no cursor moves, because there is none to move.
LiveOpOutcome liveOpDecision(int? opSeq, int? cursor) {
  if (opSeq == null || cursor == null) return LiveOpOutcome.applied;
  if (opSeq <= cursor) return LiveOpOutcome.ignored;
  if (opSeq == cursor + 1) return LiveOpOutcome.applied;
  return LiveOpOutcome.needsReconcile;
}
