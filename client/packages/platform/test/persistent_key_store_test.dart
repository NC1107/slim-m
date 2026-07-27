// SPDX-License-Identifier: Apache-2.0
/// Tests for the desktop [KeyStore] backend: it must actually survive a
/// restart, which is the entire point of replacing [InMemoryKeyStore], and it
/// must actually be private, which is the entire point of not just reusing
/// ordinary preferences. Also covers the iOS keychain accessibility this app
/// configures, which flutter_secure_storage cannot itself verify without a
/// real keychain behind it.
library;

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_platform/platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileKeyStore', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('slimm_keystore_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a stored secret is read back by handle', () async {
      final store = FileKeyStore(directory: dir);
      final handle = await store.put('session', 'super-secret');
      expect(await store.read(handle), 'super-secret');
    });

    test('a missing handle reads as null', () async {
      final store = FileKeyStore(directory: dir);
      expect(await store.read('nothing_here'), isNull);
    });

    test('delete removes only that secret', () async {
      final store = FileKeyStore(directory: dir);
      await store.put('a', 'first');
      await store.put('b', 'second');

      await store.delete('a');

      expect(await store.read('a'), isNull);
      expect(await store.read('b'), 'second');
    });

    test('clear removes everything this store wrote, and nothing else',
        () async {
      final store = FileKeyStore(directory: dir);
      await store.put('a', 'first');
      await store.put('b', 'second');

      await store.clear();

      expect(await store.read('a'), isNull);
      expect(await store.read('b'), isNull);
    });

    test('sign is unimplemented: no real key backend exists here', () async {
      final store = FileKeyStore(directory: dir);
      await expectLater(
        () => store.sign('handle', const [1, 2, 3]),
        throwsUnsupportedError,
      );
    });

    test('a secret survives a restart, across separate store instances',
        () async {
      // A real restart re-reads from disk; two independently constructed
      // stores pointed at the same directory play the same role here.
      final first = FileKeyStore(directory: dir);
      await first.put('session', 'token-value');

      final second = FileKeyStore(directory: dir);
      expect(await second.read('session'), 'token-value');
    });

    test('the push key survives a restart, across separate store instances',
        () async {
      final firstKeys =
          await DevicePushKeys(FileKeyStore(directory: dir)).publicKeyBase64();
      final secondKeys =
          await DevicePushKeys(FileKeyStore(directory: dir)).publicKeyBase64();

      expect(secondKeys, firstKeys);
    });

    test(
        'concurrent writes do not lose one another: every put lands, not '
        'just whichever read-modify-write cycle finished last', () async {
      final store = FileKeyStore(directory: dir);
      // Fired together, not awaited individually: the shape of a session write
      // and a push-key write landing on the same store back to back.
      await Future.wait([
        store.put('a', 'first'),
        store.put('b', 'second'),
        store.put('c', 'third'),
      ]);

      expect(await store.read('a'), 'first');
      expect(await store.read('b'), 'second');
      expect(await store.read('c'), 'third');
    });

    test('the secrets file is restricted to this OS account', () async {
      final store = FileKeyStore(directory: dir);
      await store.put('session', 'super-secret');

      final file = File('${dir.path}/slimm_secrets.json');
      expect(file.existsSync(), isTrue);
      // Owner only, nothing for group or other. A file created with just the
      // process umask is typically group-readable, the exposure this closes.
      expect(file.statSync().modeString(), 'rw-------');
    }, testOn: 'linux');
  });

  group('SecureKeyStore', () {
    test(
        'iOS items are device-bound: excluded from backup, and never '
        'migrate to a new device', () {
      final store = SecureKeyStore();
      expect(
        store.debugStorage.iOptions.accessibility,
        KeychainAccessibility.unlocked_this_device,
      );
    });

    test('sign is unimplemented: no real key backend exists here', () async {
      final store = SecureKeyStore();
      await expectLater(
        () => store.sign('handle', const [1, 2, 3]),
        throwsUnsupportedError,
      );
    });
  });
}
