// SPDX-License-Identifier: Apache-2.0
/// The composer's "Paste image" action: whether to offer it, and running it
/// against callbacks the composer supplies.
///
/// Split out of `composer.dart` rather than folded into its already-tight
/// line budget, and because this is more than the wrapper `_pickAttachment`
/// already has: reading the clipboard can fail in a way worth explaining
/// (see `composer_clipboard_image_stub.dart`'s [ClipboardImageReadException]),
/// where a file pick's own failures are already handled at the picker seam.
///
/// [composerClipboardPasteAvailable] is a plain [Future], never awaited
/// before opening the actions sheet: `showComposerActionsSheet` resolves it
/// itself, after the sheet is already on screen. Awaiting it first was
/// tried and reverted - a `MethodChannel` call with no handler registered
/// never completes inside a `testWidgets` pump cycle (confirmed directly;
/// it throws immediately in a bare `test()`, the only difference being
/// which zone the await runs in), so gating the sheet's very appearance on
/// it silently hung every existing test that opens this sheet without also
/// mocking a channel it has no reason to know about.
library;

import 'dart:typed_data';

import 'composer_clipboard_image.dart';

/// Whether the "+" sheet's own "Paste image" row is worth offering.
///
/// Answers [hasClipboardImage] alone, on every platform - Android's only
/// route, and iOS's too, unconditionally.
///
/// This used to also answer false whenever [editMenuPasteSwizzleInstalled]
/// reported true, on the theory that the iOS long-press edit menu's own
/// Paste item already did this with no prompt, making this row a redundant,
/// worse duplicate. That theory did not survive a real device (2026-08-01):
/// the swizzle installing is not evidence the menu item appears, and on this
/// composer's plain Material `TextField` it provably does not - see
/// `composer_clipboard_image_stub.dart`'s doc comment on
/// [editMenuPasteSwizzleInstalled] for the mechanism. Withdrawing the only
/// working route on an unproven claim left no way to paste an image at all,
/// so this row is never hidden again on that signal: only genuine evidence
/// that a paste completed through the native menu would justify hiding it,
/// and nothing here tracks that yet.
Future<bool> composerClipboardPasteAvailable() => hasClipboardImage();

/// Runs the whole "Paste image" action: clears [setError] up front, so a
/// retry that succeeds does not leave a stale failure on screen, then reads
/// the clipboard and either [stage]s the bytes (the same shape as
/// `Composer`'s own `_stageAttachment`, handed over directly rather than
/// wrapped) or reports a genuine read failure back through [setError].
/// Neither runs when the clipboard simply held no image - that is a silent
/// no-op, not a failure, the same way a cancelled file pick reports nothing.
Future<void> pasteClipboardImage(
  Future<void> Function(Uint8List bytes, String filename) stage,
  void Function(String? message) setError,
) async {
  setError(null);
  try {
    final bytes = await readClipboardImage();
    if (bytes != null) await stage(bytes, 'pasted-image.png');
  } on ClipboardImageReadException catch (e) {
    setError(e.message);
  }
}
