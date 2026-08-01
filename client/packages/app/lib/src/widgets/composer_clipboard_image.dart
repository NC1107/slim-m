// SPDX-License-Identifier: Apache-2.0
/// Reading an image straight off Ctrl+V, on the one platform that lets a
/// Flutter app see it at all.
///
/// `package:flutter/services.dart`'s own [Clipboard] carries plain text
/// only; there is no image variant on any target this client ships to,
/// short of a browser API or a native plugin. Only the web target has a
/// real implementation below this seam ([clipboardImagePasteSupported] is
/// `true` there and nowhere else); [startClipboardImagePaste] is a no-op on
/// iOS, Android, Linux, Windows and macOS desktop, so Ctrl+V keeps its
/// ordinary text-only behaviour on those rather than silently swallowing
/// the keystroke for a feature that cannot work.
library;

export 'composer_clipboard_image_stub.dart'
    if (dart.library.js_interop) 'composer_clipboard_image_web.dart';
