// SPDX-License-Identifier: Apache-2.0
/// The emoji picker's category tab row and result grid.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import 'custom_emoji_image.dart';
import 'emoji_catalog.dart';

/// The row of category tabs above the grid. Hidden by the panel while a
/// search is active, since a query already narrows the whole catalog.
class EmojiCategoryTabs extends StatelessWidget {
  const EmojiCategoryTabs({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<EmojiCategory> categories;
  final EmojiCategory selected;
  final ValueChanged<EmojiCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AppIconButton(
                icon: category.icon,
                semanticLabel: category.label,
                tooltip: category.label,
                size: AppIconButtonSize.sm,
                iconSize: AppSizes.icon16,
                active: category == selected,
                onPressed: () => onSelect(category),
              ),
            ),
        ],
      ),
    );
  }
}

/// A grid of [emoji], with [highlighted] drawing the one keyboard
/// `ArrowUp`/`ArrowDown` navigation currently sits on. Own scroll view: the
/// panel gives it a bounded height and lets it page internally.
///
/// Sized by cell rather than by column count. A fixed count makes the cell as
/// wide as whatever surface it lands in, and the same grid serves a 320pt
/// anchored popup and a bottom sheet that is 414pt on a phone and 624pt on a
/// desktop; at eight columns that last one drew 71pt cells around a 20pt
/// glyph. Against [cellExtent] the column count varies instead and every cell
/// lands between roughly 38 and 44pt on all three.
class EmojiGrid extends StatelessWidget {
  const EmojiGrid({
    super.key,
    required this.emoji,
    required this.highlighted,
    required this.onTap,
    this.shrinkWrap = false,
  });

  final List<PickerEmoji> emoji;
  final int highlighted;
  final ValueChanged<PickerEmoji> onTap;

  /// On for a caller that bounds the grid by a maximum rather than a fixed
  /// height, so a handful of tiles occupies a handful of rows.
  final bool shrinkWrap;

  /// A cell's target size, and the ceiling on its measured one. It is
  /// [AppSizes.rowTouch] because a cell is a tap target: the sheet is the
  /// touch surface, and nothing here should ask for a smaller one.
  static const double cellExtent = AppSizes.rowTouch;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: shrinkWrap,
      padding: const EdgeInsets.all(AppSpacing.s8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: cellExtent,
        mainAxisSpacing: AppSpacing.s4,
        crossAxisSpacing: AppSpacing.s4,
      ),
      itemCount: emoji.length,
      itemBuilder: (context, index) => _EmojiCell(
        emoji: emoji[index],
        highlighted: index == highlighted,
        onTap: () => onTap(emoji[index]),
      ),
    );
  }
}

/// One tile. Built directly on [FocusableActionDetector] rather than the
/// form package's `FocusableTapTarget`: that widget floors its hit target at
/// [AppSizes.rowPointer]/[AppSizes.rowTouch], which is larger than a dense
/// grid cell and would overflow it. [AppMenuItem] takes the same low-level
/// approach for the same reason.
class _EmojiCell extends StatefulWidget {
  const _EmojiCell({
    required this.emoji,
    required this.highlighted,
    required this.onTap,
  });

  final PickerEmoji emoji;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_EmojiCell> createState() => _EmojiCellState();
}

class _EmojiCellState extends State<_EmojiCell> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final fill = widget.highlighted
        ? tokens.accentSoft
        : (_hovered ? tokens.surfaceSunken : Colors.transparent);

    final content = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        border: widget.highlighted
            ? Border.all(color: tokens.accentFill)
            : null,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      foregroundDecoration: _focused
          ? BoxDecoration(
              border: Border.all(color: tokens.focusRing, width: 2),
              borderRadius: BorderRadius.circular(AppRadii.control),
            )
          : null,

      /// 20, not on AppText's scale: sized to read as a legible glyph rather
      /// than any text style, the same literal exception AppChip.reaction
      /// documents for its own emoji glyph. An uploaded image is drawn to the
      /// same 20 so the two kinds sit on one visual line.
      child: switch (widget.emoji) {
        UnicodeEmoji(:final emoji) => Text(
          emoji.char,
          style: const TextStyle(fontSize: 20, height: 1),
        ),
        DeploymentEmoji(:final emoji) => CustomEmojiImage(emojiId: emoji.id),
      },
    );

    return Semantics(
      label: widget.emoji.label,
      button: true,
      selected: widget.highlighted,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onTap(),
          ),
        },
        child: GestureDetector(onTap: widget.onTap, child: content),
      ),
    );
  }
}
