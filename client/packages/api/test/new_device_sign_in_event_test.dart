// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// [ServerEvent.parse] for `device.signed_in`: another device signed into
/// this account.
library;

import 'dart:convert';

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  test('parses a well-formed device.signed_in frame', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'device.signed_in',
        'device_id': 'd1',
        'device_name': 'Laptop',
        'client_kind': 'desktop',
        'signed_in_at': 1700000000000,
      }),
    );
    expect(event, isA<NewDeviceSignIn>());
    final signIn = event! as NewDeviceSignIn;
    expect(signIn.deviceName, 'Laptop');
    expect(signIn.clientKind, 'desktop');
    expect(signIn.signedInAt, 1700000000000);
  });

  test('a null client_kind is kept null and a missing name is ignored', () {
    final named = ServerEvent.parse(
      jsonEncode({
        'type': 'device.signed_in',
        'device_id': 'd1',
        'device_name': 'Old',
        'client_kind': null,
        'signed_in_at': 1,
      }),
    );
    expect((named! as NewDeviceSignIn).clientKind, isNull);
    final nameless = ServerEvent.parse(
      jsonEncode({
        'type': 'device.signed_in',
        'device_id': 'd1',
        'signed_in_at': 1,
      }),
    );
    expect(nameless, isNull);
  });
}
