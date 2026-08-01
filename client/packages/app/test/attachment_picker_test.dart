// SPDX-License-Identifier: Apache-2.0
/// The composer and avatar attach actions' shared picker, proven at the
/// `file_picker` method channel: nothing on this box can drive a real OS
/// picker, and `attachment_picker.dart`'s whole reason to exist is that the
/// two [AttachmentSource] routes must ask the plugin for different things.
///
/// Proves: [AttachmentSource.photoLibrary] requests `FileType.image`, which
/// is what selects the Photos-backed `PHPickerViewController` on iOS, and
/// [AttachmentSource.fileBrowser] requests the plugin's default (no `type:`
/// at all), which is what selects `UIDocumentPickerViewController` there
/// instead. Does not prove either OS actually shows a different picker for
/// that request, or that a file picked outside the camera roll decodes as a
/// usable image; neither is checkable without a phone.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/attachment_picker.dart';

const _channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');

void _mock(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => _mock(null));

  test('the photo library route asks the plugin for FileType.image', () async {
    MethodCall? seen;
    _mock((call) async {
      seen = call;
      return null; // no selection, the same shape a cancelled pick returns
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final picked = await container.read(
      attachmentPickerProvider(AttachmentSource.photoLibrary),
    )();

    expect(picked, isNull);
    expect(seen, isNotNull);
    expect(seen!.method, 'image');
  });

  test(
    'the file browser route asks the plugin for the default FileType.any',
    () async {
      MethodCall? seen;
      _mock((call) async {
        seen = call;
        return null;
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final picked = await container.read(
        attachmentPickerProvider(AttachmentSource.fileBrowser),
      )();

      expect(picked, isNull);
      expect(seen, isNotNull);
      expect(
        seen!.method,
        'any',
        reason: 'the document browser opens with no type filter at all',
      );
    },
  );
}
