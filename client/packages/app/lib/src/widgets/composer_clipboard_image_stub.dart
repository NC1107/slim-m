// SPDX-License-Identifier: Apache-2.0
/// The mobile bridge: iOS and Android both expose a real image clipboard
/// that `package:flutter/services.dart`'s own [Clipboard] cannot reach (see
/// `composer_clipboard_image.dart`'s doc comment for why that path is a dead
/// end), so this reaches it through a hand-written platform channel instead
/// - `ClipboardImagePlugin.swift` on iOS, `ClipboardImageChannel.kt` on
/// Android.
///
/// [clipboardImagePasteSupported] stays false and the two Ctrl+V hooks stay
/// no-ops here on purpose: mobile has no equivalent of the web's live
/// paste-event listener to hook. The affordance this file backs is
/// poll-and-tap instead - [hasClipboardImage] is checked once when the
/// composer's "+" sheet opens, and [readClipboardImage] runs only if the
/// person taps the row it gates - see `composer_clipboard_paste.dart`.
///
/// Desktop (Linux, Windows, macOS) registers no platform-side handler for
/// this channel at all, so a call here simply finds nothing to answer it.
/// That is treated as "not supported" rather than surfaced as a crash: both
/// functions below catch [MissingPluginException] and answer false or null.
/// It is also what makes this file exercisable in a plain `flutter test` run
/// on any host: mocking the channel stands in for the platform side on every
/// target, mobile or not.
library;

import 'package:flutter/services.dart';

/// False here; see `composer_clipboard_image_web.dart` for the one platform
/// where a live paste listener is real.
const bool clipboardImagePasteSupported = false;

/// No-op: there is no paste-event equivalent to hook on this target.
void startClipboardImagePaste(
  void Function(Uint8List bytes, String filename) onImage,
) {}

/// No-op, matching [startClipboardImagePaste].
void stopClipboardImagePaste() {}

const MethodChannel _clipboardImageChannel = MethodChannel(
  'top.npcserver.slimm/clipboard_image',
);

/// Thrown by [readClipboardImage] when the clipboard holds an image but the
/// platform could not read it - on Android, most often a `content://` URI
/// whose source app never granted read access. Never thrown for "there is no
/// image"; [readClipboardImage] answers that with null instead.
class ClipboardImageReadException implements Exception {
  const ClipboardImageReadException(this.message);

  /// A sentence fit to show, not a raw platform error string.
  final String message;

  @override
  String toString() => message;
}

/// Whether the clipboard currently holds an image, without ever raising
/// iOS's "Allow Paste?" prompt: `UIPasteboard.hasImages` is a metadata check
/// Apple explicitly exempts from that prompt, unlike reading the image value
/// itself in [readClipboardImage].
Future<bool> hasClipboardImage() async {
  try {
    return await _clipboardImageChannel.invokeMethod<bool>('hasImage') ?? false;
  } on MissingPluginException {
    return false;
  }
}

/// Reads the clipboard's image, or null if it holds none. This is the call
/// that may raise iOS's paste prompt, once per install, since it reads the
/// pasteboard's actual value rather than metadata about it.
Future<Uint8List?> readClipboardImage() async {
  try {
    return await _clipboardImageChannel.invokeMethod<Uint8List>('readImage');
  } on MissingPluginException {
    return null;
  } on PlatformException catch (e) {
    throw ClipboardImageReadException(
      e.message ?? 'The clipboard image could not be read.',
    );
  }
}
