// SPDX-License-Identifier: Apache-2.0
/// [MethodChannelLinuxTrayProbe]'s own invariant, stated in its doc comment
/// and otherwise completely unproven before this file: absent, false, and
/// an error must all read as false, the one property decision 0012's
/// close-to-tray feature depends on to never hide a window behind a tray
/// that does not exist, with no way back.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/tray/linux_tray_probe.dart';

const _channel = MethodChannel('top.npcserver.slimm/linux_tray_probe');
const _probe = MethodChannelLinuxTrayProbe();

void _mock(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => _mock(null));

  test('a true reply reports a host is registered', () async {
    _mock((call) async => true);

    expect(await _probe.isHostRegistered(), isTrue);
  });

  test('a false reply reports no host', () async {
    _mock((call) async => false);

    expect(await _probe.isHostRegistered(), isFalse);
  });

  test('a null reply reads as no host, not a crash', () async {
    _mock((call) async => null);

    expect(await _probe.isHostRegistered(), isFalse);
  });

  test('a thrown PlatformException reads as no host', () async {
    _mock((call) async {
      throw PlatformException(code: 'boom', message: 'watcher unreachable');
    });

    expect(await _probe.isHostRegistered(), isFalse);
  });

  test('no handler registered at all reads as no host, the shape a fresh '
      'session with no watcher on the bus actually takes', () async {
    expect(await _probe.isHostRegistered(), isFalse);
  });
}
