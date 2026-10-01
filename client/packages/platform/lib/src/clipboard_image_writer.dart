// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Putting an image on the system clipboard, which Flutter's own `Clipboard`
/// cannot do: it carries plain text only.
///
/// The seam takes a future of the bytes rather than the bytes themselves,
/// because a browser only honours a clipboard write started inside the tap
/// that asked for it, and fetching a full-size image can outlast that.
library;

import 'dart:typed_data';

import 'clipboard_image_writer_io.dart'
    if (dart.library.js_interop) 'clipboard_image_writer_web.dart' as impl;

/// A clipboard write the platform refused or could not perform.
class ClipboardImageWriteException implements Exception {
  const ClipboardImageWriteException(this.message);

  /// A sentence fit to show, not a raw platform error string.
  final String message;

  @override
  String toString() => message;
}

abstract class ClipboardImageWriter {
  /// Copies the image [bytes] resolves to, in whatever encoding the source
  /// has; the writer converts to the format its platform wants.
  ///
  /// Throws [ClipboardImageWriteException] when the platform refuses.
  Future<void> writeImage(Future<Uint8List> bytes);
}

class PlatformClipboardImageWriter implements ClipboardImageWriter {
  const PlatformClipboardImageWriter();

  @override
  Future<void> writeImage(Future<Uint8List> bytes) => impl.writeImage(bytes);
}
