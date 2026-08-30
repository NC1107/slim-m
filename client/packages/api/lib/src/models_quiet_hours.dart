// SPDX-License-Identifier: Apache-2.0
/// The caller's own quiet-hours window: an optional time-of-day span,
/// stored server-side in minutes since midnight UTC.
///
/// Split out of models.dart purely to stay under this repo's line budget.
library;

/// A quiet-hours window, in minutes since midnight UTC.
///
/// [startMinute] and [endMinute] are not ordered the way a plain range
/// would be: [startMinute] may be greater than [endMinute] for a window
/// that crosses midnight (23:00-08:00 is the ordinary shape, not an edge
/// case). Converting to and from the account's local clock is entirely a
/// client concern - see `utcMinutesFromLocalTimeOfDay`/`localTimeOfDayFromUtcMinutes` in
/// `client/packages/app/lib/src/providers/quiet_hours_controller.dart` -
/// this type only ever carries UTC.
class QuietHours {
  const QuietHours({required this.startMinute, required this.endMinute});

  final int startMinute;
  final int endMinute;

  factory QuietHours.fromJson(Map<String, dynamic> json) => QuietHours(
        startMinute: json['start_minute'] as int,
        endMinute: json['end_minute'] as int,
      );

  Map<String, dynamic> toJson() => {
        'start_minute': startMinute,
        'end_minute': endMinute,
      };
}
