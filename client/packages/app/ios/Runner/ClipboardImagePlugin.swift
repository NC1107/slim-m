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
/// `hasImage`/`readImage` below back the composer's "+" sheet row: a poll
/// (metadata only, never prompts) and a tap (a real pasteboard read, which
/// **prompts on every call** - confirmed on a real device 2026-08-01, not
/// once per install as first assumed; see `ClipboardPasteBridge.m` for the
/// route that does not prompt at all.
///
/// `editMenuPasteAvailable` reports whether `ClipboardPasteBridge.m`'s
/// swizzle actually installed. The composer prefers that route and only
/// falls back to this poll-and-tap one when it did not - either because a
/// future Flutter engine upgrade renamed the class or selectors it depends
/// on, or on Android, which has no such swizzle at all.
enum ClipboardImagePlugin {
  static let name = "top.npcserver.slimm/clipboard_image"

  /// Set once, from `AppDelegate`, to `SlimmInstallClipboardPasteBridge`'s
  /// own return value.
  static var editMenuPasteAvailable = false

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasImage":
      result(UIPasteboard.general.hasImages)
    case "readImage":
      result(UIPasteboard.general.image?.pngData())
    case "editMenuPasteAvailable":
      result(editMenuPasteAvailable)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
