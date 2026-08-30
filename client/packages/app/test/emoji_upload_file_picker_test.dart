// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The emoji upload card's default picker, proven at the `file_picker`
/// method channel: nothing on this box can drive a real OS picker.
///
/// Proves: the plugin request now asks for `FileType.custom` with an
/// extension filter, not `FileType.image`, which is what selects
/// `UIDocumentPickerViewController` over `PHPickerViewController` on iOS
/// (`IOSFilePickerHandler.swift`) and the full SAF browser over a media-only
/// one on Android. Does not prove either OS actually shows a different
/// picker for that request, or that a document picked outside the camera
/// roll decodes as a usable image; neither is checkable without a phone.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/admin/emoji_upload_card.dart';

const _channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');

void _mock(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => _mock(null));

  test('the picker asks the plugin for FileType.custom with an extension '
      'filter, not FileType.image', () async {
    MethodCall? seen;
    _mock((call) async {
      seen = call;
      return null; // no selection, the same shape a cancelled pick returns
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final picked = await container.read(emojiImagePickerProvider)();

    expect(picked, isNull);
    expect(seen, isNotNull);
    expect(
      seen!.method,
      'custom',
      reason: 'FileType.image would send method "image" instead',
    );
    final arguments = seen!.arguments as Map;
    expect(arguments['allowedExtensions'], acceptedEmojiExtensions);
  });
}
