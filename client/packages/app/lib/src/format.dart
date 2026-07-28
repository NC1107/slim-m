// SPDX-License-Identifier: Apache-2.0
/// Small formatting helpers with no state and no dependency on `intl`,
/// matching `formatMessageTime` in `widgets/message_row_identity.dart`.
library;

/// `YYYY-MM-DD HH:mm`, local time. Used wherever a screen shows a Unix
/// millisecond timestamp that is not a message (a report, an invite, a
/// role) and so has no chat-specific "today" shorthand to reach for.
String formatDateTime(int epochMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final y = dt.year.toString().padLeft(4, '0');
  final mo = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final mi = dt.minute.toString().padLeft(2, '0');
  return '$y-$mo-$d $h:$mi';
}
