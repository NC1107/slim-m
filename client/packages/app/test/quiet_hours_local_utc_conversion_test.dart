// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// `utcMinutesFromLocalTimeOfDay`/`localTimeOfDayFromUtcMinutes`
/// (`quiet_hours_controller.dart`): the client-only conversion between this
/// device's local wall clock and the UTC minutes the wire carries.
///
/// Deliberately round-trip rather than asserting a fixed offset: the test
/// runner's own time zone is whatever the host happens to be, so a fixed
/// "23:00 local is 1380 UTC" assertion would only be true in one zone. A
/// round trip through both conversions holds regardless of which zone that
/// is, which is exactly the property the server-side minute comparison
/// depends on.
library;

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/quiet_hours_controller.dart';

void main() {
  test('every minute of day round-trips local to UTC and back', () {
    for (var minute = 0; minute < 24 * 60; minute += 7) {
      final local = TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
      final utcMinutes = utcMinutesFromLocalTimeOfDay(local);
      expect(utcMinutes, inInclusiveRange(0, 1439));
      final roundTripped = localTimeOfDayFromUtcMinutes(utcMinutes);
      expect(roundTripped, local);
    }
  });

  test('midnight converts to a valid minute, not a negative one', () {
    final utcMinutes = utcMinutesFromLocalTimeOfDay(
      const TimeOfDay(hour: 0, minute: 0),
    );
    expect(utcMinutes, inInclusiveRange(0, 1439));
  });
}
