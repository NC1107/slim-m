// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Dropping the Live Text / "Scan Text" entry from a text field's
/// long-press menu.
///
/// The platform offers it on every editable field, and it is noise in all of
/// them here: nothing in this product is a form you would photograph a
/// document into. Backlog #129 asked for it gone from the composer, and it
/// was - but only from the composer, so every other field in the app kept
/// offering it: the gif search, a channel name, a category name, the sign-in
/// fields. This is the same filter, one layer down, where a field can reach
/// it without depending on the app.
///
/// Two shapes because the framework has two. A field that can use the iOS
/// system menu gets [IOSSystemContextMenuItem]s and is rendered natively;
/// everything else gets [ContextMenuButtonItem]s in Flutter's own adaptive
/// toolbar. Both carry a Live Text entry and both need it removed, so a fix
/// to one alone leaves the other showing it.
library;

import 'package:flutter/material.dart';

/// [defaults] with the iOS system menu's Live Text item dropped.
///
/// Pure, so it can be tested without a field, a platform channel, or a
/// running iOS.
List<IOSSystemContextMenuItem> systemContextMenuItemsWithoutScanText(
  List<IOSSystemContextMenuItem> defaults,
) =>
    defaults
        .where((item) => item is! IOSSystemContextMenuItemLiveText)
        .toList();

/// [defaults] with the adaptive toolbar's Live Text button dropped - the
/// non-iOS-system-menu counterpart of [systemContextMenuItemsWithoutScanText].
/// Pure for the same reason.
List<ContextMenuButtonItem> contextMenuButtonItemsWithoutScanText(
  List<ContextMenuButtonItem> defaults,
) =>
    defaults
        .where((item) => item.type != ContextMenuButtonType.liveTextInput)
        .toList();

/// `TextField`'s own default menu with Live Text taken out, and nothing else
/// changed.
///
/// The composer builds its own instead, because it has a second thing to do
/// that no other field does - forcing Paste into the iOS system menu so an
/// image-only clipboard offers one. It filters Live Text through these same
/// two functions, so the two menus cannot drift on the part they share.
Widget textContextMenuWithoutScanText(
  BuildContext context,
  EditableTextState editableTextState,
) {
  if (SystemContextMenu.isSupportedByField(editableTextState)) {
    return SystemContextMenu.editableText(
      editableTextState: editableTextState,
      items: systemContextMenuItemsWithoutScanText(
        SystemContextMenu.getDefaultItems(editableTextState),
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
