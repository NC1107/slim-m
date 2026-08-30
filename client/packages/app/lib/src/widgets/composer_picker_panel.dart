// SPDX-License-Identifier: Apache-2.0
/// The composer's own Emoji/GIFs picker: `EmojiPickerPanel`'s content under
/// an Emoji tab, `gif_picker.dart`'s `GifPickerBody` under a GIFs tab, both
/// inside one floating card - there is no third picker implementation here.
/// `composer_picker_button.dart` anchors and opens this.
///
/// Stickers are deliberately absent. Nothing in this repo models a sticker -
/// no server type, no schema entry, no client model - so there is no tab for
/// one to hide behind. The configured GIF provider happens to expose a
/// stickers endpoint too, but adding a whole new media kind is a product
/// decision for the owner, not something to slip in alongside this fix.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

import 'emoji_picker_panel.dart';
import 'gif_picker.dart' show GifPickerBody;

/// Which half of the panel is showing.
enum ComposerPickerTab { emoji, gif }

class ComposerPickerPanel extends StatefulWidget {
  const ComposerPickerPanel({
    super.key,
    required this.initialTab,
    required this.onSelectEmoji,
    required this.onPickedGif,
    required this.onClose,
    this.showGifTab = true,
    this.width = pickerWidth,
  });

  final ComposerPickerTab initialTab;
  final ValueChanged<String> onSelectEmoji;
  final ValueChanged<api.Attachment> onPickedGif;
  final VoidCallback onClose;

  /// Off for a deployment with no GIF provider configured, matching the
  /// button's own `gifSearchEnabled` gate: no tab for a feature that has
  /// nowhere to reach.
  final bool showGifTab;
  final double width;

  @override
  State<ComposerPickerPanel> createState() => _ComposerPickerPanelState();
}

class _ComposerPickerPanelState extends State<ComposerPickerPanel> {
  late ComposerPickerTab _tab = widget.initialTab;

  static const _tabOptions = [
    AppSegmentedOption(label: 'Emoji'),
    AppSegmentedOption(label: 'GIFs'),
  ];

  void _selectTab(int index) =>
      setState(() => _tab = ComposerPickerTab.values[index]);

  @override
  Widget build(BuildContext context) {
    final close = activatorFor(AppAction.escape);
    return CallbackShortcuts(
      // The emoji tab's own search/grid nav lives inside EmojiPickerPanel.
      bindings: {if (close != null) close: widget.onClose},
      child: AppMenu(
        width: widget.width,
        children: [
          if (widget.showGifTab)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s8,
                AppSpacing.s8,
                AppSpacing.s8,
                AppSpacing.s4,
              ),
              child: AppSegmentedControl.inline(
                options: _tabOptions,
                selectedIndex: ComposerPickerTab.values.indexOf(_tab),
                onSegmentSelected: _selectTab,
                semanticLabel: 'Emoji or GIFs',
              ),
            ),
          switch (_tab) {
            ComposerPickerTab.emoji => EmojiPickerPanel(
              chrome: false,
              width: widget.width,
              onSelect: widget.onSelectEmoji,
              onClose: widget.onClose,
            ),
            ComposerPickerTab.gif => GifPickerBody(
              onPicked: widget.onPickedGif,
            ),
          },
        ],
      ),
    );
  }
}
