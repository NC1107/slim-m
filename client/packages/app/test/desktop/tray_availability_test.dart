// SPDX-License-Identifier: Apache-2.0
/// Whether a tray is reachable right now, decision 0012's split: macOS and
/// Windows are unconditional, Linux asks the runtime probe every time.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/close_behavior.dart';
import 'package:slimm_app/src/desktop/tray/linux_tray_probe.dart';
import 'package:slimm_app/src/desktop/tray/tray_availability.dart';

class _FakeLinuxTrayProbe implements LinuxTrayProbe {
  _FakeLinuxTrayProbe(this.answer);
  bool answer;
  int callCount = 0;

  @override
  Future<bool> isHostRegistered() async {
    callCount++;
    return answer;
  }
}

void main() {
  group('trayAvailabilityCheck', () {
    test('macOS never consults the Linux probe', () async {
      final probe = _FakeLinuxTrayProbe(false);
      final check = trayAvailabilityCheck(
        platform: DesktopPlatform.macOS,
        probe: probe,
      );

      expect(await check(), isTrue);
      expect(probe.callCount, 0);
    });

    test('Windows never consults the Linux probe', () async {
      final probe = _FakeLinuxTrayProbe(false);
      final check = trayAvailabilityCheck(
        platform: DesktopPlatform.windows,
        probe: probe,
      );

      expect(await check(), isTrue);
      expect(probe.callCount, 0);
    });

    test('Linux defers entirely to the probe\'s live answer', () async {
      final probe = _FakeLinuxTrayProbe(true);
      final check = trayAvailabilityCheck(
        platform: DesktopPlatform.linux,
        probe: probe,
      );

      expect(await check(), isTrue);

      probe.answer = false;
      expect(
        await check(),
        isFalse,
        reason: 'a host can disappear mid-session, so this must never cache',
      );
      expect(probe.callCount, 2);
    });
  });
}
