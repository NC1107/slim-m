// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The native clipboard write: the PNG that crosses the channel, and what a
/// platform with no handler or a refusing one turns into.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_platform/platform.dart';

const _channel = MethodChannel('top.npcserver.slimm/clipboard_image');

final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAT0lEQVR42u3PQQkA'
  'AAgEsAtmMCMaywi+hcEKLNP1WgQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE'
  'BAQEBAQEBAQEBAQEBAQEBAQELguFPsFaQDQP9QAAAABJRU5ErkJggg==',
);

// A 1x1 GIF, a format no clipboard here takes.
final Uint8List _gif = base64Decode(
  'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
);

void _handle(Future<Object?>? Function(MethodCall) handler) {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
}

void main() {
  const writer = PlatformClipboardImageWriter();

  test('a PNG crosses the channel unchanged', () async {
    Object? sent;
    _handle((call) async {
      expect(call.method, 'writeImage');
      sent = call.arguments;
      return null;
    });

    await writer.writeImage(Future.value(_png));

    expect(sent, _png);
  });

  test('a GIF is re-encoded as PNG before it crosses', () async {
    Uint8List? sent;
    _handle((call) async {
      sent = call.arguments as Uint8List;
      return null;
    });

    await writer.writeImage(Future.value(_gif));

    expect(isPng(sent!), isTrue);
  });

  test('bytes no codec can read are refused with a sentence', () async {
    _handle((call) async => null);

    await expectLater(
      writer.writeImage(Future.value(Uint8List.fromList([1, 2, 3]))),
      throwsA(isA<ClipboardImageWriteException>()),
    );
  });

  test('a platform with no handler says copying is unsupported', () async {
    await expectLater(
      writer.writeImage(Future.value(_png)),
      throwsA(
        isA<ClipboardImageWriteException>().having(
          (e) => e.message,
          'message',
          contains('not supported'),
        ),
      ),
    );
  });

  test('a platform refusal surfaces its own message', () async {
    _handle((call) async =>
        throw PlatformException(code: 'write_failed', message: 'Denied.'));

    await expectLater(
      writer.writeImage(Future.value(_png)),
      throwsA(
        isA<ClipboardImageWriteException>().having(
          (e) => e.message,
          'message',
          'Denied.',
        ),
      ),
    );
  });
}
