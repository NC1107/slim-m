// SPDX-License-Identifier: Apache-2.0
/// Screen-share audio is offered only where the underlying capture can
/// actually deliver it, the same `audio_gain_test.dart` shape for a
/// different capability.
///
/// Every branch is driven through the `platform` override rather than the
/// real `lk.lkPlatform()` alone: this project's own CI and local `flutter
/// test` both run on Linux, which is itself one of the platforms this
/// capability answers true for, so a plain "does it match the real host"
/// comparison would let a hardcoded `true` slip through unnoticed on the one
/// environment this suite actually runs in.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:slimm_rtc/rtc.dart';

void main() {
  test('web and Linux can publish it', () {
    expect(
      supportsScreenShareAudio(platform: lk.PlatformType.web),
      isTrue,
    );
    expect(
      supportsScreenShareAudio(platform: lk.PlatformType.linux),
      isTrue,
    );
  });

  test('macOS, iOS, Android and Windows cannot', () {
    for (final platform in [
      lk.PlatformType.macOS,
      lk.PlatformType.iOS,
      lk.PlatformType.android,
      lk.PlatformType.windows,
    ]) {
      expect(
        supportsScreenShareAudio(platform: platform),
        isFalse,
        reason: '$platform has no path to a published audio track',
      );
    }
  });

  test('with no override, it asks the real platform', () {
    final onLinuxOrWeb = {
      lk.PlatformType.web,
      lk.PlatformType.linux,
    }.contains(lk.lkPlatform());
    expect(supportsScreenShareAudio(), onLinuxOrWeb);
  });
}
