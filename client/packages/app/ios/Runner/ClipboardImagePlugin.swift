// SPDX-License-Identifier: Apache-2.0
import Flutter
import UIKit

/// The app half of the composer's mobile paste bridge; the Dart half is
/// `composer_clipboard_image_stub.dart`, which owns the channel name.
///
/// Flutter's own paste path cannot reach this: `EditableText.pasteText()`
/// only ever calls `Clipboard.getData(Clipboard.kTextPlain)`, and the
/// engine's `FlutterTextInputPlugin.canPerformAction:` deliberately answers
/// `hasStrings` for the system `paste:` action - "Forbid pasting images,
/// memojis, or other non-string content," in its own comment. So a real
/// image paste on iOS needs a hand-written bridge, not an extension of the
/// text-editing path.
///
/// The two methods below are deliberately not the same operation.
/// `hasImages` is `UIPasteboard`'s own metadata check, one of the ones iOS
/// 16's paste-consent system explicitly exempts from its "Allow Paste?"
/// prompt. `image` reads the pasteboard's actual value, which is exactly
/// the kind of read that prompt exists for, so calling it is what may raise
/// that prompt - once per install, the first time this app asks.
enum ClipboardImagePlugin {
  static let name = "top.npcserver.slimm/clipboard_image"

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasImage":
      result(UIPasteboard.general.hasImages)
    case "readImage":
      result(UIPasteboard.general.image?.pngData())
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
