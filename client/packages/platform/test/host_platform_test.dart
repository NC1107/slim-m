// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Tests for the host-OS seam the web build needs, and for the key-store
/// backend it decides.
///
/// These run on the Dart VM, so `kIsWeb` is always false here and only the
/// native half of each guard is reachable. That is the half that ships, and
/// it is the half a "simplification" of the guard would silently change; the
/// browser half is verified by running the built app in a browser, which no
/// VM test can stand in for.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_platform/platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('host platform', () {
    test('reports the same OS dart:io does, rather than inverting it', () {
      expect(isIOSHost, Platform.isIOS);
      expect(isAndroidHost, Platform.isAndroid);
    });

    test('a desktop host is neither mobile platform', () {
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        expect(isIOSHost, isFalse);
        expect(isAndroidHost, isFalse);
      }
    });
  });

  group('deviceDisplayName', () {
    // Guards the bug: every device used to read the literal string 'desktop'.
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('two different platforms produce two different device names', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final android = deviceDisplayName;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final mac = deviceDisplayName;

      expect(android, isNot(mac));
    });

    test('the same platform is stable across calls', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;

      expect(deviceDisplayName, deviceDisplayName);
    });

    test('never the literal string every device used to share', () {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        expect(deviceDisplayName, isNot('desktop'));
        expect(deviceDisplayName, isNotEmpty);
      }
    });
  });

  group('createPersistentKeyStore', () {
    test('desktop gets the owner-only file, never the keychain backend', () {
      if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
        return;
      }
      // Guards the documented desktop tradeoff: flutter_secure_storage's
      // Linux backend needs a keyring agent that plenty of sessions lack.
      expect(createPersistentKeyStore(), isA<FileKeyStore>());
    });

    test('mobile gets the platform keychain', () {
      if (!Platform.isIOS && !Platform.isAndroid) return;
      expect(createPersistentKeyStore(), isA<SecureKeyStore>());
    });
  });
}
