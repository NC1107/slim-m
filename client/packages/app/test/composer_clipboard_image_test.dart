// SPDX-License-Identifier: Apache-2.0
/// The composer's mobile clipboard-image bridge, proven at the platform
/// channel: nothing on this box can drive a real iOS or Android pasteboard.
///
/// Proves the Dart-side contract only - that [hasClipboardImage] and
/// [readClipboardImage] call the right method with the right shape, and that
/// a platform failure becomes [ClipboardImageReadException] rather than a
/// silent null. It does not and cannot prove what `UIPasteboard` or
/// `ClipboardManager` actually do, or that iOS's "Allow Paste?" prompt
/// behaves the way `ClipboardImagePlugin.swift`'s doc comment reasons; that
/// needs a device.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/composer_clipboard_image.dart';

const _channel = MethodChannel('top.npcserver.slimm/clipboard_image');

void _mock(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => _mock(null));

  test('hasClipboardImage asks the platform for hasImage', () async {
    MethodCall? seen;
    _mock((call) async {
      seen = call;
      return true;
    });

    expect(await hasClipboardImage(), isTrue);
    expect(seen?.method, 'hasImage');
  });

  test('hasClipboardImage answers false with no platform handler', () async {
    expect(await hasClipboardImage(), isFalse);
  });

  test('readClipboardImage asks the platform for readImage and returns its '
      'bytes', () async {
    MethodCall? seen;
    _mock((call) async {
      seen = call;
      return Uint8List.fromList([1, 2, 3]);
    });

    final bytes = await readClipboardImage();
    expect(seen?.method, 'readImage');
    expect(bytes, [1, 2, 3]);
  });

  test(
    'readClipboardImage answers null for "no image", not an error',
    () async {
      _mock((call) async => null);
      expect(await readClipboardImage(), isNull);
    },
  );

  test('readClipboardImage answers null with no platform handler', () async {
    expect(await readClipboardImage(), isNull);
  });

  test('a platform read failure becomes ClipboardImageReadException carrying '
      'the platform message, not a silent null', () async {
    _mock((call) async {
      throw PlatformException(
        code: 'read_failed',
        message:
            'The app that copied this image did not allow it to be '
            'read.',
      );
    });

    await expectLater(
      readClipboardImage,
      throwsA(
        isA<ClipboardImageReadException>().having(
          (e) => e.message,
          'message',
          'The app that copied this image did not allow it to be read.',
        ),
      ),
    );
  });
}
