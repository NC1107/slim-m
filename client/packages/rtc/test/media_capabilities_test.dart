// SPDX-License-Identifier: Apache-2.0
/// Tests for the runtime media capability probe.
///
/// The branches that matter are the unhappy ones. A portal that answers with
/// zero sources and a portal that throws are different situations reported the
/// same way to the user, and neither can be reproduced on a CI runner, so they
/// are driven through the probe seam here instead.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_rtc/rtc.dart';

class _FakeProbe implements MediaDevicesProbe {
  _FakeProbe(
      {this.micTracks, this.screenSources, this.micError, this.screenError});

  final int? micTracks;
  final int? screenSources;
  final Object? micError;
  final Object? screenError;

  @override
  Future<int> countMicrophoneTracks() async {
    if (micError != null) throw micError!;
    return micTracks!;
  }

  @override
  Future<int> countScreenSources() async {
    if (screenError != null) throw screenError!;
    return screenSources!;
  }
}

void main() {
  group('microphone', () {
    test('an open mic with tracks is available', () async {
      final caps = MediaCapabilities(probe: _FakeProbe(micTracks: 1));
      final result = await caps.microphone();
      expect(result.supported, isTrue);
      expect(result.detail, contains('1 audio track'));
    });

    test('a stream with no audio track is not a working microphone', () async {
      // Some platforms hand back a stream and then no track, which reads as
      // success if you only check that nothing threw.
      final caps = MediaCapabilities(probe: _FakeProbe(micTracks: 0));
      final result = await caps.microphone();
      expect(result.supported, isFalse);
      expect(result.error, contains('no audio track'));
    });

    test('a refusal is reported verbatim, not swallowed', () async {
      final caps = MediaCapabilities(
        probe: _FakeProbe(micError: StateError('NotAllowedError')),
      );
      final result = await caps.microphone();
      expect(result.supported, isFalse);
      expect(result.error, contains('NotAllowedError'));
    });
  });

  group('screen capture', () {
    test('sources offered by the portal count as available', () async {
      final caps = MediaCapabilities(probe: _FakeProbe(screenSources: 3));
      final result = await caps.screenCapture();
      expect(result.supported, isTrue);
      expect(result.detail, contains('3 source'));
    });

    test('a portal that offers nothing is unavailable, not a crash', () async {
      // This is the dismissed-picker case, and the shape the old PipeWire bug
      // produced. It has to be an ordinary answer.
      final caps = MediaCapabilities(probe: _FakeProbe(screenSources: 0));
      final result = await caps.screenCapture();
      expect(result.supported, isFalse);
      expect(result.error, contains('no capturable sources'));
    });

    test('a portal that throws is reported with what it said', () async {
      final caps = MediaCapabilities(
        probe: _FakeProbe(screenError: StateError('xdg-desktop-portal absent')),
      );
      final result = await caps.screenCapture();
      expect(result.supported, isFalse);
      expect(result.error, contains('xdg-desktop-portal absent'));
    });
  });

  test('probeAll reports every capability, including the failing ones',
      () async {
    final caps = MediaCapabilities(
      probe: _FakeProbe(micTracks: 1, screenSources: 0),
    );
    final all = await caps.probeAll();
    expect(all.keys, containsAll(['microphone', 'screen_capture']));
    expect(all['microphone']!.supported, isTrue);
    expect(all['screen_capture']!.supported, isFalse,
        reason: 'one capability failing must not hide the others');
  });
}
