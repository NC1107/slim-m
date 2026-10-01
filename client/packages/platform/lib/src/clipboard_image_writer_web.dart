// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The browser route: the async clipboard API with an `image/png` blob.
///
/// The `ClipboardItem` is handed a promise for the blob and `write` is called
/// before anything is awaited, because Safari (and Chrome after a few
/// seconds) only honours a write begun inside the user gesture. Writing needs
/// a secure context, so a plain-http deployment is refused and reported.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'clipboard_image_png.dart';
import 'clipboard_image_writer.dart';

Future<void> writeImage(Future<Uint8List> source) async {
  final clipboard = web.window.navigator.clipboard;
  final blob = _pngBlob(source);
  final record = JSObject()..setProperty('image/png'.toJS, blob.toJS);
  try {
    await clipboard.write([web.ClipboardItem(record)].toJS).toDart;
  } catch (_) {
    throw const ClipboardImageWriteException(
      'The browser would not copy this image. Try Save image instead.',
    );
  }
}

Future<JSAny?> _pngBlob(Future<Uint8List> source) async {
  final png = await toPng(await source);
  return web.Blob(
    [png.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
}
