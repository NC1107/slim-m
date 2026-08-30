// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The caller's own quiet-hours window: an optional local time-of-day span
/// during which an `everything` notification preference is narrowed to
/// `mentions` (`push::recipients::narrow_for_notification_preference` on the
/// server). Mirrors [notificationPreferenceProvider]: a real `GET` backs
/// this, not a local echo.
library;

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'providers.dart';

/// The caller's current window, fetched fresh whenever watched. `null` means
/// disabled - the server default, and what every account that predates this
/// feature keeps.
final quietHoursProvider = FutureProvider.autoDispose<api.QuietHours?>(
  (ref) => ref.watch(apiProvider).quietHours(),
);

/// Converts a local wall-clock time into UTC minutes since midnight, the
/// wire unit `api.QuietHours` carries. Anchored to today's date, the same
/// simplification every "what time is it right now" conversion in this app
/// already makes; a window set right at a DST transition can read an hour
/// off until re-saved, which is an acceptable cost for never asking the
/// server to know the account's time zone at all.
int utcMinutesFromLocalTimeOfDay(TimeOfDay local) {
  final now = DateTime.now();
  final localDateTime = DateTime(
    now.year,
    now.month,
    now.day,
    local.hour,
    local.minute,
  );
  final utc = localDateTime.toUtc();
  return utc.hour * 60 + utc.minute;
}

/// The inverse of [utcMinutesFromLocalTimeOfDay]: UTC minutes since midnight
/// back to a local wall-clock time, for rendering a window this account
/// already set.
TimeOfDay localTimeOfDayFromUtcMinutes(int utcMinutes) {
  final now = DateTime.now().toUtc();
  final utcDateTime = DateTime.utc(
    now.year,
    now.month,
    now.day,
    utcMinutes ~/ 60,
    utcMinutes % 60,
  );
  final local = utcDateTime.toLocal();
  return TimeOfDay(hour: local.hour, minute: local.minute);
}
