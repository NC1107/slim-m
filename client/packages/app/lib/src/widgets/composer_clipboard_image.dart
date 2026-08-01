// SPDX-License-Identifier: Apache-2.0
/// Reading an image straight off Ctrl+V, on the one platform that lets a
/// Flutter app see it at all.
///
/// `package:flutter/services.dart`'s own [Clipboard] carries plain text
/// only; there is no image variant on any target this client ships to,
/// short of a browser API or a native plugin. Confirmed against the engine
/// itself, not just the Dart docs: `EditableText.pasteText()` only ever
/// calls `Clipboard.getData(Clipboard.kTextPlain)`, `FlutterPlatformPlugin`'s
/// `getClipboardData:` on iOS reads `pasteboard.string` alone with no image
/// branch, and `FlutterTextInputPlugin`'s `canPerformAction:` deliberately
/// returns `hasStrings` for the system Paste action - "Forbid pasting
/// images, memojis, or other non-string content," in the engine's own
/// comment. So Cmd+V and the system Paste item are both dead ends on every
/// platform, not merely unimplemented on this one.
///
/// [startClipboardImagePaste]/[stopClipboardImagePaste] are the event-driven
/// half of this seam, real only on web ([clipboardImagePasteSupported] is
/// `true` there and nowhere else): a no-op on iOS, Android, Linux, Windows
/// and macOS, so Ctrl+V keeps its ordinary text-only behaviour on those
/// rather than silently swallowing the keystroke for a feature that cannot
/// work through it.
///
/// [hasClipboardImage]/[readClipboardImage] are the second, poll-and-tap
/// half, real on iOS and Android through a hand-written platform channel
/// (see `composer_clipboard_image_stub.dart`) and a no-op on web and
/// desktop. A composer offers a "Paste image" action rather than a
/// keystroke there, because neither an iOS `paste:` action nor Android's
/// `ClipboardManager` reaches a Flutter app without one being deliberately
/// invoked - see `composer_clipboard_paste.dart`.
library;

export 'composer_clipboard_image_stub.dart'
    if (dart.library.js_interop) 'composer_clipboard_image_web.dart';
