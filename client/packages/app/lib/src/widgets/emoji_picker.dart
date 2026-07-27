// SPDX-License-Identifier: Apache-2.0
/// The emoji picker: a floating, searchable, categorised surface opened from
/// the add-reaction control on a message hover, or from a bottom sheet where
/// there is no pointer to hover with.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:emojis/emoji.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

import '../providers/recent_emoji.dart';
import 'emoji_catalog.dart';
import 'emoji_picker_grid.dart';

import 'message_row.dart';

/// The panel's own measured size, like the command palette's `_paletteWidth`
/// beside it; neither is on the spacing grid.
const double _pickerWidth = 320;
const double _gridHeight = 260;

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

/// The floating surface itself: search, category tabs, and the grid they
/// filter. Exposed on its own so a test can pump it without the button's
/// overlay plumbing around it.
class EmojiPickerPanel extends ConsumerStatefulWidget {
  const EmojiPickerPanel({
    super.key,
    required this.onSelect,
    required this.onClose,
    this.autofocusSearch = true,
    this.width = _pickerWidth,
  });

  final ValueChanged<String> onSelect;
  final VoidCallback onClose;

  /// Off in a sheet: an autofocused search field raises the soft keyboard
  /// over the grid before the user has seen any of it.
  final bool autofocusSearch;

  /// Overridable so the panel can shrink to a narrow phone rather than
  /// overflow its sheet.
  final double width;

  @override
  ConsumerState<EmojiPickerPanel> createState() => _EmojiPickerPanelState();
}

class _EmojiPickerPanelState extends ConsumerState<EmojiPickerPanel> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  EmojiCategory _category = EmojiCategory.smileysEmotion;
  int _highlighted = 0;

  /// The last frame's flat result list, so a key handler (which runs outside
  /// build) can act on exactly what is on screen, the same convention the
  /// command palette uses for its own `_visible`.
  List<Emoji> _visible = const [];

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _highlighted = 0;
    });
  }

  void _selectCategory(EmojiCategory category) {
    setState(() {
      _category = category;
      _query = '';
      _searchController.clear();
      _highlighted = 0;
    });
  }

  void _move(int delta) {
    if (_visible.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta) % _visible.length;
      if (_highlighted < 0) _highlighted += _visible.length;
    });
  }

  void _pick(Emoji emoji) {
    unawaited(ref.read(recentEmojiProvider.notifier).use(emoji.char));
    widget.onSelect(emoji.char);
  }

  void _pickHighlighted() {
    if (_visible.isEmpty) return;
    _pick(_visible[_highlighted]);
  }

  Map<ShortcutActivator, VoidCallback> _bindings() {
    final close = activatorFor(AppAction.escape);
    return {
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
      if (close != null) close: widget.onClose,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final recent = ref.watch(recentEmojiProvider);
    final searching = _query.trim().isNotEmpty;

    final results = searching
        ? searchEmoji(_query)
        : (_category == EmojiCategory.recent
              ? recentEmojiEntries(recent)
              : emojiForCategory(_category.group!));
    _visible = results;
    if (_highlighted >= results.length) {
      _highlighted = results.isEmpty ? 0 : results.length - 1;
    }

    final tabs = [
      if (recent.isNotEmpty) EmojiCategory.recent,
      ...emojiCategoriesInOrder,
    ];

    return CallbackShortcuts(
      bindings: _bindings(),
      child: Material(
        type: MaterialType.transparency,
        child: AppMenu(
          width: widget.width,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s8),
              child: AppInput(
                controller: _searchController,
                focusNode: _searchFocus,
                autofocus: widget.autofocusSearch,
                placeholder: 'Search emoji',
                icon: Icon(
                  AppIcons.search,
                  size: AppSizes.icon16,
                  color: tokens.textSecondary,
                ),
                onChanged: _onQueryChanged,
                onSubmitted: (_) => _pickHighlighted(),
                semanticLabel: 'Search emoji',
              ),
            ),
            if (!searching) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                child: EmojiCategoryTabs(
                  categories: tabs,
                  selected: _category,
                  onSelect: _selectCategory,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
            ],
            const AppMenuDivider(),
            SizedBox(
              height: _gridHeight,
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        'No matches.',
                        style: AppText.body.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    )
                  : EmojiGrid(
                      emoji: results,
                      highlighted: _highlighted,
                      onTap: _pick,
                    ),
            ),
          ],
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
                _pickerWidth,
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
