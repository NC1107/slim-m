// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The native route: one `writeImage` call on the channel the composer's
/// paste bridge already owns (`composer_clipboard_image_stub.dart`), answered
/// by a hand-written handler on iOS, Android, Linux, Windows and macOS.
library;

import 'package:flutter/services.dart';

import 'clipboard_image_png.dart';
import 'clipboard_image_writer.dart';

const MethodChannel _channel = MethodChannel(
  'top.npcserver.slimm/clipboard_image',
);

Future<void> writeImage(Future<Uint8List> source) async {
  final Uint8List png;
  try {
    png = await toPng(await source);
  } on FormatException {
    throw const ClipboardImageWriteException(
      'This image could not be converted for the clipboard.',
    );
  }
  try {
    await _channel.invokeMethod<void>('writeImage', png);
  } on MissingPluginException {
    throw const ClipboardImageWriteException(
      'Copying images is not supported on this device.',
    );
  } on PlatformException catch (e) {
    throw ClipboardImageWriteException(
      e.message ?? 'The clipboard refused the image.',
    );
  }
}
