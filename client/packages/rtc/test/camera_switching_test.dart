// SPDX-License-Identifier: Apache-2.0
/// Tests for [CameraSwitching.setEnabled] and the [CameraToggleResult] it
/// returns, in particular the wrapping that lets [VoiceSession.lastError]
/// keep answering with one `Object?` while still carrying a
/// [CameraFailureReason] for a caller that wants one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_rtc/rtc.dart';

class _NoCameras implements CameraDevices {
  @override
  Future<List<CameraDevice>> list() async => const [];
}

void main() {
  group('CameraToggleResult', () {
    test('ok carries no cause and no reason', () {
      const result = CameraToggleResult.ok();
      expect(result.ok, isTrue);
      expect(result.error, isNull);
    });

    test('a failure with no reason reports the bare cause unwrapped', () {
      final result = CameraToggleResult.failed('boom', null);
      expect(result.ok, isFalse);
      expect(result.error, same('boom'));
    });

    test('a failure with a reason wraps the cause in a CameraFailure', () {
      final result = CameraToggleResult.failed(
        'boom',
        CameraFailureReason.permissionDenied,
      );
      final wrapped = result.error;
      expect(wrapped, isA<CameraFailure>());
      expect((wrapped as CameraFailure).cause, 'boom');
      expect(wrapped.reason, CameraFailureReason.permissionDenied);
    });
  });

  group('CameraSwitching.setEnabled', () {
    test('a null local participant is a no-op success', () async {
      final switching = CameraSwitching(_NoCameras());
      final result = await switching.setEnabled(null, true);
      expect(result.ok, isTrue);
    });
  });
}
