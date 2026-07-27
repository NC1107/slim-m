// SPDX-License-Identifier: Apache-2.0
/// Tests for the device push keypair: generated once, reused after, and
/// never shared between devices.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_platform/platform.dart';

void main() {
  group('DevicePushKeys', () {
    test('the public key is base64 of 32 raw bytes', () async {
      final publicKey =
          await DevicePushKeys(InMemoryKeyStore()).publicKeyBase64();
      expect(base64Decode(publicKey), hasLength(32));
    });

    test('a keypair is generated once and reused, not regenerated', () async {
      final store = InMemoryKeyStore();
      final first = await DevicePushKeys(store).publicKeyBase64();

      // A fresh DevicePushKeys over the same store stands in for a later
      // launch: a changed answer means the private key was never persisted.
      final second = await DevicePushKeys(store).publicKeyBase64();

      expect(second, first);
    });

    test('two devices never end up with the same key', () async {
      final a = await DevicePushKeys(InMemoryKeyStore()).publicKeyBase64();
      final b = await DevicePushKeys(InMemoryKeyStore()).publicKeyBase64();
      expect(a, isNot(b));
    });
  });
}
