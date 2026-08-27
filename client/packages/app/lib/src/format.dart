// SPDX-License-Identifier: Apache-2.0
/// Small formatting helpers with no state and no dependency on `intl`,
/// matching `formatMessageTime` in `widgets/message_row_identity.dart`.
library;

/// `YYYY-MM-DD HH:mm` or `YYYY-MM-DD h:mm AM/PM`, local time, following
/// [use24Hour] - resolved once per caller from `resolveUse24Hour` in
/// `providers/display_preferences.dart`, since this file has no widget
/// context of its own to read it from. Used wherever a screen shows a Unix
/// millisecond timestamp that is not a message (a report, an invite, a
/// role) and so has no chat-specific "today" shorthand to reach for.
String formatDateTime(int epochMs, {required bool use24Hour}) {
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final y = dt.year.toString().padLeft(4, '0');
  final mo = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final time = use24Hour
      ? '${dt.hour.toString().padLeft(2, '0')}:'
            '${dt.minute.toString().padLeft(2, '0')}'
      : _h12(dt);
  return '$y-$mo-$d $time';
}

String _h12(DateTime dt) {
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final suffix = dt.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $suffix';
}

/// The hours/minutes/seconds a [Duration] breaks into, shared by
/// `CallDuration`'s ticking clock and `formatCallDuration`'s fixed recap
/// string (`widgets/call_participant_tiles.dart` and
/// `widgets/call_recap_card.dart`), which show that breakdown differently on
/// purpose - only the arithmetic to get h/m/s out of the same [Duration] was
/// duplicated.
({int hours, int minutes, int seconds}) decomposeDuration(Duration d) =>
    (hours: d.inHours, minutes: d.inMinutes % 60, seconds: d.inSeconds % 60);
