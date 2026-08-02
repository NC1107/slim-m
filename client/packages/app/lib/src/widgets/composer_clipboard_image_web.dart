// SPDX-License-Identifier: Apache-2.0
/// The web implementation: the browser's own `paste` DOM event, which hands
/// over pasted bytes directly with no extra permission prompt.
///
/// This deliberately does not use the async `navigator.clipboard.read()`
/// API: that one needs an explicit clipboard-read permission grant, while a
/// `paste` event is the browser's ordinary reaction to Ctrl+V and needs
/// none. Only an item whose MIME type starts with `image/` is treated as a
/// pasted image; anything else (plain text, the common case) is left alone,
/// so the browser's own default paste still lands wherever Flutter's text
/// field is really backed by an `<input>` or `<textarea>`.
///
/// State here is module-level rather than per-instance because the seam it
/// backs ([startClipboardImagePaste]) is itself a pair of top-level
/// functions: only one composer is ever focused at a time, so one active
/// listener is all this needs to hold.
///
/// [hasClipboardImage] and [readClipboardImage] are the mobile seam's
/// poll-and-tap pair (see `composer_clipboard_image_stub.dart`); the browser
/// has no permission-free way to check clipboard contents ahead of a real
/// paste, so both are no-ops here and the "Paste image" row they gate never
/// shows on web - Ctrl+V through the listener above is already the way in.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// True: the browser's `paste` event is a real, working source of image
/// bytes on this target.
const bool clipboardImagePasteSupported = true;

void Function(Uint8List bytes, String filename)? _onImage;
JSFunction? _listener;

/// Starts listening for a pasted image; call once per focus gained, paired
/// with [stopClipboardImagePaste] on focus lost.
void startClipboardImagePaste(
  void Function(Uint8List bytes, String filename) onImage,
) {
  stopClipboardImagePaste();
  _onImage = onImage;
  final listener = _handlePaste.toJS;
  _listener = listener;
  web.document.addEventListener('paste', listener);
}

/// Stops listening; safe to call even if nothing was ever started.
void stopClipboardImagePaste() {
  final listener = _listener;
  if (listener != null) {
    web.document.removeEventListener('paste', listener);
  }
  _listener = null;
  _onImage = null;
}

/// Always false: see this file's doc comment for why the browser cannot
/// answer this without a permission prompt of its own.
Future<bool> hasClipboardImage() async => false;

/// Always null, matching [hasClipboardImage].
Future<Uint8List?> readClipboardImage() async => null;

/// Always false: the edit-menu swizzle this backs on iOS
/// (`composer_clipboard_image_stub.dart`) has no browser equivalent.
Future<bool> editMenuPasteSwizzleInstalled() async => false;

void _handlePaste(web.ClipboardEvent event) =>
    unawaited(_readPastedImage(event));

Future<void> _readPastedImage(web.ClipboardEvent event) async {
  final onImage = _onImage;
  final items = event.clipboardData?.items;
  if (onImage == null || items == null) return;
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (!item.type.startsWith('image/')) continue;
    final file = item.getAsFile();
    if (file == null) continue;
    // Stops the browser also treating this as a text or file-drop paste.
    event.preventDefault();
    final buffer = await file.arrayBuffer().toDart;
    onImage(buffer.toDart.asUint8List(), _filenameFor(item.type));
    return;
  }
}

String _filenameFor(String mimeType) {
  final extension = switch (mimeType) {
    'image/png' => 'png',
    'image/jpeg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    _ => 'png',
  };
  return 'pasted-image.$extension';
}

/// The web half of the seam's exception type.
///
/// Declared here as well as in the stub because the two are conditional-
/// import siblings: a caller writing `on ClipboardImageReadException` must
/// compile on every target, and a type that exists on one side only fails
/// dart2js while passing `dart analyze` outright. That is exactly how the
/// web build broke without any gate noticing.
///
/// Nothing on this target throws it - the browser paste event hands over
/// bytes or nothing - but the type must exist for the catch to compile.
class ClipboardImageReadException implements Exception {
  const ClipboardImageReadException(this.message);

  /// A sentence fit to show, not a raw platform error string.
  final String message;

  @override
  String toString() => message;
}
