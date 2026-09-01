// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The composer field's long-press/right-click menu: forcing the iOS 16+
/// system menu to offer Paste for an image, which it never does on its own.
///
/// `TextField`'s default `contextMenuBuilder` (`text_field.dart:892-899`)
/// asks `SystemContextMenu` for `getDefaultItems`, which reads
/// `EditableTextState.contextMenuButtonItems`, whose `paste` entry is gated
/// on `Clipboard.hasStrings()` alone (`editable_text.dart:2660`) - an
/// image-only pasteboard never gets a `paste` entry into the list Dart sends
/// native at all. See PR #327 ("Image paste on iPhone, confirmed working")
/// entry for the full trace through the engine and framework source, and
/// confirmation this now works end to end on a real iPhone.
///
/// The fix does not need a custom system-menu item: [SystemContextMenu.items]
/// accepts an explicit list, and `IOSSystemContextMenuItemPaste` is the
/// platform's own built-in Paste - "handled by the platform," no Dart
/// callback runs when it is tapped. Forcing it into that list is what makes
/// native ask, for the first time, whether `paste:` can run on the field,
/// and `ClipboardPasteBridge.m`'s swizzle already answers that for an image
/// with no prompt (`canPerformAction:` returns YES from `hasImages`, which
/// Apple exempts, and the swizzled `paste:` reads the image inside that same
/// native dispatch). Nothing native changes here: the swizzle was always
/// correct, only unreachable, because Dart never asked for a paste item to
/// exist at all when the clipboard held no string.
///
/// Confirmed against `FlutterTextInputPlugin.mm`'s own
/// `editMenuInteraction:menuForConfiguration:suggestedActions:`: a requested
/// `"paste"` entry is resolved by searching the *native* `suggestedActions`
/// tree - the one UIKit computes from `canPerformAction:` on the field -
/// for a `UICommand` whose action is `paste:`. A custom item would not take
/// this path: its `onPressed` runs in Dart, one method-channel round trip
/// after the tap is already dispatched, which is not the exempt route -
/// only the system's own Paste command is.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart'
    show
        contextMenuButtonItemsWithoutScanText,
        systemContextMenuItemsWithoutScanText;

import 'composer_clipboard_image.dart';

/// Whether the clipboard holds an image, refreshed only through
/// [hasClipboardImage]'s metadata check - never the prompting
/// [readClipboardImage] - so nothing here ever raises iOS's "Allow Paste?"
/// prompt on its own. Mirrors `text_selection.dart`'s own
/// `ClipboardStatusNotifier`: attaches as a lifecycle observer on
/// construction and refreshes on the app resuming, so a copy made in another
/// app is picked up without the composer field needing to be touched first.
class ClipboardImageStatusNotifier extends ValueNotifier<bool>
    with WidgetsBindingObserver {
  ClipboardImageStatusNotifier() : super(false) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(update());
  }

  bool _disposed = false;

  /// Re-checks the clipboard; safe to call as often as a caller likes, since
  /// [hasClipboardImage] is a metadata read with no consent cost.
  Future<void> update() async {
    final hasImage = await hasClipboardImage();
    if (_disposed) return;
    value = hasImage;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(update());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    super.dispose();
  }
}

/// [defaults] plus the system's own Paste item, unless it is already there
/// or [clipboardHasImage] says the clipboard has nothing worth offering it
/// for. Pure and platform-independent on purpose, so a test can drive it
/// directly with no device and no [SystemContextMenu] involved at all.
@visibleForTesting
List<IOSSystemContextMenuItem> systemContextMenuItemsWithForcedPaste(
  List<IOSSystemContextMenuItem> defaults, {
  required bool clipboardHasImage,
}) {
  final items = List<IOSSystemContextMenuItem>.of(defaults);
  final offersPaste = items
      .whereType<IOSSystemContextMenuItemPaste>()
      .isNotEmpty;
  if (clipboardHasImage && !offersPaste) {
    items.add(const IOSSystemContextMenuItemPaste());
  }
  return items;
}

/// Matches `TextField`'s own default builder except for two changes: see
/// this file's doc comment for why forcing Paste in is enough, and why a
/// custom item would not be; and backlog #129 for why the Live Text /
/// "Scan Text" item is dropped from both the iOS system menu and the
/// adaptive toolbar it falls back to elsewhere.
Widget composerContextMenuBuilder(
  BuildContext context,
  EditableTextState editableTextState, {
  required bool clipboardHasImage,
}) {
  if (SystemContextMenu.isSupportedByField(editableTextState)) {
    return SystemContextMenu.editableText(
      editableTextState: editableTextState,
      items: systemContextMenuItemsWithForcedPaste(
        systemContextMenuItemsWithoutScanText(
          SystemContextMenu.getDefaultItems(editableTextState),
        ),
        clipboardHasImage: clipboardHasImage,
      ),
    );
  }
  return AdaptiveTextSelectionToolbar.buttonItems(
    buttonItems: contextMenuButtonItemsWithoutScanText(
      editableTextState.contextMenuButtonItems,
    ),
    anchors: editableTextState.contextMenuAnchors,
  );
}
