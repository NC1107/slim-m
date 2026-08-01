// SPDX-License-Identifier: Apache-2.0
/// The non-web fallback: nothing on this seam can reach an image on the
/// clipboard, so both calls below are no-ops. See
/// `composer_clipboard_image.dart`'s doc comment for why.
library;

import 'dart:typed_data';

/// False here; see the web implementation for the one platform where this
/// is true.
const bool clipboardImagePasteSupported = false;

/// No-op: there is no platform hook to attach on this target.
void startClipboardImagePaste(
  void Function(Uint8List bytes, String filename) onImage,
) {}

/// No-op, matching [startClipboardImagePaste].
void stopClipboardImagePaste() {}
