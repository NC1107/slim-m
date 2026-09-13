// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// What happened to a DM call, attached to the message that records it.
///
/// A call is an event in a conversation, so it rides the transcript rather
/// than a log of its own - which means it orders, paginates, syncs and marks
/// unread like any other message, with nothing in any of those paths having to
/// know calls exist.
///
/// Split out of models.dart purely to stay under this repo's line budget.
library;

/// How a DM call ended.
///
/// [timedOut] is the missed call - nobody answered before the ring's own
/// timeout - and is the reason this whole record exists: until it did, a call
/// nobody picked up left no trace anywhere, so the person who missed it never
/// found out. [canceled] is the caller hanging up first, which the other side
/// also never answered.
enum CallOutcome {
  answered,
  declined,
  canceled,
  timedOut;

  /// The wire spelling, which is snake_case where this is camelCase.
  static CallOutcome? fromWire(String raw) => switch (raw) {
        'answered' => CallOutcome.answered,
        'declined' => CallOutcome.declined,
        'canceled' => CallOutcome.canceled,
        'timed_out' => CallOutcome.timedOut,
        // An outcome this build never heard of renders as a plain call.
        _ => null,
      };

  /// Whether nobody ever spoke: the three ways a call did not happen.
  bool get wasMissed => this != CallOutcome.answered;
}

/// The call a [Message] records, or null on an ordinary message.
class CallRecord {
  const CallRecord({
    required this.outcome,
    this.callerId,
    this.durationMs,
  });

  /// Null once an unrecognised outcome arrives, and null for a caller whose
  /// account has been deleted - the same convention a message's own
  /// `authorId` follows.
  final String? callerId;

  /// Null when the server named an outcome this build does not know. The
  /// message still renders as a call, which is the honest degrade: something
  /// call-shaped happened and this build cannot say what.
  final CallOutcome? outcome;

  /// How long the call lasted. Null for every outcome but [CallOutcome.answered],
  /// and null on an answered call until the duration is known.
  final int? durationMs;

  factory CallRecord.fromJson(Map<String, dynamic> json) => CallRecord(
        callerId: json['caller_id'] as String?,
        outcome: CallOutcome.fromWire(json['outcome'] as String),
        durationMs: (json['duration_ms'] as num?)?.toInt(),
      );
}
