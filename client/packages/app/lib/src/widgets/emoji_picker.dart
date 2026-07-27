// SPDX-License-Identifier: Apache-2.0
/// The emoji picker's two entry points: a floating surface opened from the
/// add-reaction control on a message hover, and a bottom sheet where there is
/// no pointer to hover with. Both wrap the one [EmojiPickerPanel], re-exported
/// here so a caller needs this import only.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import 'emoji_picker_panel.dart';
import 'message_row.dart';

export 'emoji_picker_panel.dart' show EmojiPickerPanel;

/// The add-reaction glyph, anchored so its picker opens beneath it and
/// closes on an outside tap, an escape, or a pick. Mirrors the server
/// menu's own `CompositedTransformTarget`/`OverlayPortal` pairing in
/// `channel_rail_frame.dart`.
class EmojiPickerButton extends StatefulWidget {
  const EmojiPickerButton({super.key, required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  State<EmojiPickerButton> createState() => _EmojiPickerButtonState();
}

class _EmojiPickerButtonState extends State<EmojiPickerButton> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  /// Keeps the row that reveals this button on hover from unmounting it while
  /// the panel is open, since reaching the panel takes the pointer off the row.
  void _setOpen(bool open) {
    HoverRevealScope.maybeOf(context)?.pin(open);
    open ? _controller.show() : _controller.hide();
  }

  void _select(String emoji) {
    _setOpen(false);
    widget.onSelect(emoji);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        // Positioned so the follower sizes to its content: an overlay child is
        // otherwise laid out against the whole screen, which a Column fills.
        overlayChildBuilder: (context) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 4),
            child: TapRegion(
              onTapOutside: (_) => _setOpen(false),
              child: EmojiPickerPanel(
                onSelect: _select,
                onClose: () => _setOpen(false),
              ),
            ),
          ),
        ),
        child: AppIconButton(
          icon: AppIcons.smile,
          semanticLabel: 'Add a reaction',
          iconSize: AppSizes.icon16,
          onPressed: () => _setOpen(!_controller.isShowing),
        ),
      ),
    );
  }
}

/// Opens the picker as a bottom sheet: the touch-reachable counterpart to
/// [EmojiPickerButton]'s hover-anchored overlay, wrapping the same panel
/// rather than a second implementation of it.
///
/// [onSelect] runs after the sheet has popped, so a caller that moves focus
/// (the composer re-focusing its field) is not fighting the closing route.
Future<void> showEmojiPickerSheet(
  BuildContext context, {
  required ValueChanged<String> onSelect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      // Inside the keyboard inset, so the two cancel out: the route already
      // removes the top padding, which is why this matches its sibling sheet.
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmojiPickerPanel(
              autofocusSearch: false,
              width: math.min(
                pickerWidth,
                MediaQuery.sizeOf(context).width - AppSpacing.s32,
              ),
              onSelect: (emoji) {
                Navigator.of(context).pop();
                onSelect(emoji);
              },
              onClose: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}
