// SPDX-License-Identifier: Apache-2.0
/// Tests for the FCM data-message-to-notification-text mapping: the two
/// kinds that should alert someone, and every kind (including none at all)
/// that must stay silent.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/push/android_push_messages.dart';

void main() {
  group('genericAlertTextFor', () {
    test('message gets the same fixed line iOS shows', () {
      expect(genericAlertTextFor('message'), 'New message');
    });

    test('mention gets its own fixed line, distinct from a plain message', () {
      expect(genericAlertTextFor('mention'), 'You were mentioned');
    });

    test('call stays silent here: it rings through its own path', () {
      expect(genericAlertTextFor('call'), isNull);
    });

    test('wake stays silent: it is a background sync hint, not an alert', () {
      expect(genericAlertTextFor('wake'), isNull);
    });

    test('an unrecognised kind stays silent rather than guessing', () {
      expect(genericAlertTextFor('something-future-and-unknown'), isNull);
    });

    test('a missing kind stays silent rather than throwing', () {
      expect(genericAlertTextFor(null), isNull);
    });
  });
}
