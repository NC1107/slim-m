// SPDX-License-Identifier: Apache-2.0
/// Tests for [passesActivationThreshold], the pure function behind
/// [VoiceSession.setSpeakingSensitivity]. Driven directly with plain values
/// rather than a fake `lk.Participant` - the class is abstract and its own
/// constructors are private to `livekit_client`, so a real one cannot be
/// built here, the same limitation `camera_switching_test.dart`'s own doc
/// comment already names for a different livekit type.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_rtc/rtc.dart';

void main() {
  test('the SFU saying no is final, however loud the reported level', () {
    expect(passesActivationThreshold(false, 1.0, 1.0), isFalse);
  });

  test(
      'default sensitivity (1.0) matches behaviour before this existed: '
      'any reported level at all passes', () {
    expect(passesActivationThreshold(true, 0.0, 1.0), isTrue);
  });

  test('sensitivity 0 requires the loudest possible reported level', () {
    expect(passesActivationThreshold(true, 0.99, 0.0), isFalse);
    expect(passesActivationThreshold(true, 1.0, 0.0), isTrue);
  });

  test('the floor is linear between the two extremes', () {
    // sensitivity 0.5 -> floor 0.5.
    expect(passesActivationThreshold(true, 0.4, 0.5), isFalse);
    expect(passesActivationThreshold(true, 0.6, 0.5), isTrue);
  });

  test('a sensitivity outside 0-1 is clamped rather than inverted', () {
    expect(passesActivationThreshold(true, 0.01, 5.0), isTrue);
    expect(passesActivationThreshold(true, 0.99, -5.0), isFalse);
  });
}
