// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/self_update/self_update_target.dart';
import 'package:slimm_app/src/desktop/self_update/update_manifest.dart';

void main() {
  late Directory root;
  late String exe;

  setUp(() {
    root = Directory.systemTemp.createTempSync('slimm-target-arch-');
    exe = '${root.path}/0.90.0/slimm_app';
    File(exe).createSync(recursive: true);
    Link('${root.path}/current').createSync('0.90.0');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('the manifest key follows the architecture, never a constant', () {
    expect(updatePlatformKey(os: 'linux', arch: 'x64'), 'linux-x64');
    expect(updatePlatformKey(os: 'linux', arch: 'arm64'), isNull);
    expect(updatePlatformKey(os: 'windows', arch: 'arm64'), isNull);
    expect(updatePlatformKey(os: 'freebsd', arch: 'x64'), isNull);
  });

  test('an unsupported architecture gets no install target at all', () {
    expect(
      installTargetFor(exe, 'linux', arch: 'x64')?.platformKey,
      'linux-x64',
    );
    expect(installTargetFor(exe, 'linux', arch: 'arm64'), isNull);
    expect(installTargetFor(exe, 'windows', arch: 'arm64'), isNull);
  });

  test('the host architecture is read from the Dart version string', () {
    expect(hostArchitecture('3.13.0 (stable) on "linux_arm64"'), 'arm64');
    expect(hostArchitecture('3.13.0 (stable) on "windows_x64"'), 'x64');
    expect(hostArchitecture('nonsense'), 'unknown');
  });

  test('a plain version is digits and dots and nothing else', () {
    expect(isPlainVersion('0.90.0'), isTrue);
    for (final bad in ['1.2', '1.2.3.4', '1.2.3-rc', '../1.2.3', '1.2.3/x']) {
      expect(isPlainVersion(bad), isFalse, reason: bad);
    }
  });
}
