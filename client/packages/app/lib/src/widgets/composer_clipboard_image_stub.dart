// SPDX-License-Identifier: Apache-2.0
/// The mobile-and-Linux-desktop bridge: iOS, Android and Linux each expose a
/// real image clipboard that `package:flutter/services.dart`'s own
/// [Clipboard] cannot reach (see `composer_clipboard_image.dart`'s doc
/// comment for why that path is a dead end), so this reaches it through a
/// hand-written platform channel instead - `ClipboardImagePlugin.swift` on
/// iOS, `ClipboardImageChannel.kt` on Android,
/// `linux/runner/clipboard_image_channel.cc` on Linux (GTK's
/// `gtk_clipboard_wait_for_image`, encoded to PNG before it crosses the
/// channel).
///
/// Two distinct routes share this one channel, and only iOS has both.
///
/// [hasClipboardImage]/[readClipboardImage] are poll-and-tap: checked once
/// when the composer's "+" sheet opens, read only if the person taps the row
/// they gate - see `composer_clipboard_paste.dart`. [readClipboardImage] may
/// raise iOS's "Allow Paste?" prompt **on every call**, confirmed on a real
/// device 2026-08-01 (an earlier note here said once per install, which did
/// not survive contact with a phone).
///
/// [startClipboardImagePaste]/[stopClipboardImagePaste] back the better
/// route on iOS: `ClipboardPasteBridge.m` swizzles Flutter's own private text
/// input view so the system edit menu's Paste item works for an image with
/// no prompt at all, then hands the bytes to this channel's Dart side as a
/// `pastedImage` call - native-initiated, the mirror image of the poll-and-
/// tap pair above. Registering the handler here while the composer's field
/// has focus (see `Composer._handleFocusChange`) is what makes this the same
/// seam `composer_clipboard_image_web.dart`'s live paste-event listener
/// already is, even though the two triggers (a DOM event, a native menu tap)
/// share nothing else. It is inert on Android and Linux: nothing there ever
/// calls `pastedImage`, so registering the handler costs nothing.
///
/// [editMenuPasteSwizzleInstalled] reports only whether that swizzle
/// installed, never whether the menu it targets actually offers Paste -
/// confirmed on a real device 2026-08-01 that those are different things,
/// see `composer_clipboard_paste.dart`'s doc comment for why nothing here
/// gates the fallback row on it any more.
///
/// Windows and macOS register no platform-side handler at all, and neither
/// does Android for the swizzle-only calls, so a call here simply finds
/// nothing to answer it. That is treated as "not supported" rather than
/// surfaced as a crash: every function below catches [MissingPluginException]
/// and answers false or null. It is also what makes this file exercisable in
/// a plain `flutter test` run on any host: mocking the channel stands in for
/// the platform side on every target, whether or not that target has a real
/// one.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// False here; see `composer_clipboard_image_web.dart` for the one platform
/// where a live Ctrl+V/paste-event listener is real. The native edit-menu
/// route [startClipboardImagePaste] backs on iOS is a menu action, not a
/// keystroke, so it is not what this flag is about.
const bool clipboardImagePasteSupported = false;

/// Whether a Ctrl+V keystroke should ask the image clipboard itself, rather
/// than waiting to be handed an image by [startClipboardImagePaste].
///
/// True everywhere except iOS. It is not a claim that the platform has an
/// image clipboard: [hasClipboardImage] already answers false wherever no
/// handler is registered, so this being true on Windows and macOS costs one
/// channel call that finds nothing.
///
/// iOS is the one exclusion, and for a specific reason rather than caution:
/// [readClipboardImage] raises the "Allow Paste?" prompt on **every** call
/// there, so polling it from a keystroke would prompt on every paste of
/// plain text. iOS already has the route that avoids that entirely, the
/// edit-menu swizzle behind [startClipboardImagePaste].
bool get pasteKeystrokeReadsClipboardImage =>
    defaultTargetPlatform != TargetPlatform.iOS;

const MethodChannel _clipboardImageChannel = MethodChannel(
  'top.npcserver.slimm/clipboard_image',
);

void Function(Uint8List bytes, String filename)? _onPastedImage;

/// Starts listening for an image the iOS edit menu's Paste item hands over;
/// call once per focus gained, paired with [stopClipboardImagePaste] on
/// focus lost - see this file's doc comment for why a native menu tap is
/// treated as the same seam as the web listener it mirrors.
void startClipboardImagePaste(
  void Function(Uint8List bytes, String filename) onImage,
) {
  _onPastedImage = onImage;
  _clipboardImageChannel.setMethodCallHandler(_handlePastedImageCall);
}

/// Stops listening; safe to call even if nothing was ever started.
void stopClipboardImagePaste() {
  _onPastedImage = null;
  _clipboardImageChannel.setMethodCallHandler(null);
}

Future<void> _handlePastedImageCall(MethodCall call) async {
  if (call.method != 'pastedImage') return;
  final bytes = call.arguments as Uint8List?;
  if (bytes != null) _onPastedImage?.call(bytes, 'pasted-image.png');
}

/// Thrown by [readClipboardImage] when the clipboard holds an image but the
/// platform could not read it - on Android, most often a `content://` URI
/// whose source app never granted read access; on Linux, a PNG encode
/// failure after a real `GdkPixbuf` was already in hand. Never thrown for
/// "there is no image"; [readClipboardImage] answers that with null instead.
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
/// that raises iOS's paste prompt, on every call (see this file's doc
/// comment), since it reads the pasteboard's actual value rather than
/// metadata about it.
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

/// Whether `ClipboardPasteBridge.m`'s swizzle installed on the native side -
/// true only on iOS, and only once `AppDelegate` has run; false with no
/// platform handler at all (Android, desktop) and false if a future Flutter
/// engine upgrade moved the private class or selectors it depends on.
///
/// This is **not**, by itself, whether the system edit menu offers Paste for
/// an image: Flutter's default `contextMenuBuilder` on iOS 16+ routes
/// through `SystemContextMenu`, which decided the menu's contents in Dart
/// from `Clipboard.hasStrings()` alone, before any native call happened -
/// confirmed on a real device 2026-08-01 that this value could be true while
/// the menu still offered no Paste. `composer_context_menu.dart` closes that
/// gap by forcing the platform's own Paste item into the list whenever the
/// clipboard holds an image, which is what makes native ask
/// `canPerformAction:` at all; confirmed working end to end on a real
/// iPhone 2026-08-02. See `composer_clipboard_paste.dart`'s doc comment and
/// CLAUDE.md's "Image paste on iPhone, confirmed working" entry.
Future<bool> editMenuPasteSwizzleInstalled() async {
  try {
    return await _clipboardImageChannel.invokeMethod<bool>(
          'editMenuPasteSwizzleInstalled',
        ) ??
        false;
  } on MissingPluginException {
    return false;
  }
}
