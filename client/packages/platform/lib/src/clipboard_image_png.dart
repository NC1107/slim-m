// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Re-encoding an image as PNG, the one format every clipboard here takes.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

const List<int> _pngSignature = [
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a
];

bool isPng(Uint8List bytes) {
  if (bytes.length < _pngSignature.length) return false;
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) return false;
  }
  return true;
}

/// [bytes] unchanged when already PNG, else its first frame re-encoded.
///
/// Throws [FormatException] for bytes no codec can decode.
Future<Uint8List> toPng(Uint8List bytes) async {
  if (isPng(bytes)) return bytes;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      if (data == null) throw const FormatException('PNG encode failed');
      return data.buffer.asUint8List();
    } finally {
      codec.dispose();
    }
  } on Exception catch (e) {
    if (e is FormatException) rethrow;
    throw FormatException('Image could not be decoded: $e');
  }
}
