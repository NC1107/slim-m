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
/// `editMenuPasteSwizzleInstalled` reports only whether
/// `ClipboardPasteBridge.m`'s swizzle installed on the native side - not
/// whether the system edit menu it targets actually offers Paste for an
/// image. Confirmed on a real device 2026-08-01 that those are different
/// claims: this composer's plain Material `TextField` routes its menu
/// through Flutter's `SystemContextMenu`, which decides Paste's presence in
/// Dart before any native call, so the swizzle below is provably never
/// consulted there regardless of this value. The "+" sheet's own row is
/// never hidden on this signal for exactly that reason - see
/// `composer_clipboard_paste.dart`.
enum ClipboardImagePlugin {
  static let name = "top.npcserver.slimm/clipboard_image"

  /// Set once, from `AppDelegate`, to `SlimmInstallClipboardPasteBridge`'s
  /// own return value.
  static var editMenuPasteSwizzleInstalled = false

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasImage":
      result(UIPasteboard.general.hasImages)
    case "readImage":
      result(UIPasteboard.general.image?.pngData())
    case "editMenuPasteSwizzleInstalled":
      result(editMenuPasteSwizzleInstalled)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
