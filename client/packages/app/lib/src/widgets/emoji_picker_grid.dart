// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
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

/// The vertical rail beside the browse view's continuous scroll: one icon
/// per section, jumping the scroll position there rather than filtering the
/// grid the way [EmojiCategoryTabs] does. See `emoji_sectioned_grid.dart`
/// for the jump itself and why it does not track live scroll position.
class EmojiCategoryRail extends StatelessWidget {
  const EmojiCategoryRail({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<EmojiCategory> categories;

  /// Null before any jump has been made; see `emoji_sectioned_grid.dart`.
  final EmojiCategory? selected;
  final ValueChanged<EmojiCategory> onSelect;

  /// The rail's own fixed width, so a caller sizing the grid beside it does
  /// not have to measure this.
  static const double width = 32;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: SingleChildScrollView(
        child: Column(
          children: [
            for (final category in categories)
              Padding(
                // 2 is literal: no token sits between nothing and s4 here.
                padding: const EdgeInsets.symmetric(vertical: 2),
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
    this.onHoverChange,
    this.onPressChange,
  });

  final List<PickerEmoji> emoji;
  final int highlighted;
  final ValueChanged<PickerEmoji> onTap;

  /// On for a caller that bounds the grid by a maximum rather than a fixed
  /// height, so a handful of tiles occupies a handful of rows.
  final bool shrinkWrap;

  /// Null everywhere this grid does not feed a preview footer - only the
  /// composer's browse view (`composer_emoji_browse.dart`) does, for its
  /// search results.
  final void Function(PickerEmoji emoji, bool active)? onHoverChange;
  final void Function(PickerEmoji emoji, bool active)? onPressChange;

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
      itemBuilder: (context, index) {
        final tile = emoji[index];
        return EmojiCell(
          emoji: tile,
          highlighted: index == highlighted,
          onTap: () => onTap(tile),
          onHoverChange: onHoverChange == null
              ? null
              : (active) => onHoverChange!(tile, active),
          onPressChange: onPressChange == null
              ? null
              : (active) => onPressChange!(tile, active),
        );
      },
    );
  }
}

/// One tile. Built directly on [FocusableActionDetector] rather than the
/// form package's `FocusableTapTarget`: that widget floors its hit target at
/// [AppSizes.rowPointer]/[AppSizes.rowTouch], which is larger than a dense
/// grid cell and would overflow it. [AppMenuItem] takes the same low-level
/// approach for the same reason.
///
/// Public (not `_`-prefixed) so `emoji_sectioned_grid.dart` can place these
/// directly in its own sliver grids rather than [EmojiGrid]'s bounded one.
class EmojiCell extends StatefulWidget {
  const EmojiCell({
    super.key,
    required this.emoji,
    required this.highlighted,
    required this.onTap,
    this.onHoverChange,
    this.onPressChange,
  });

  final PickerEmoji emoji;
  final bool highlighted;
  final VoidCallback onTap;

  /// Feeds the preview footer: hover is the pointer's own story, a held
  /// press ([onPressChange]) is touch's - see desktop-vs-mobile.md's rule 1
  /// on every hover affordance needing a named long-press-shaped equivalent.
  final ValueChanged<bool>? onHoverChange;
  final ValueChanged<bool>? onPressChange;

  @override
  State<EmojiCell> createState() => _EmojiCellState();
}

class _EmojiCellState extends State<EmojiCell> {
  bool _hovered = false;
  bool _focused = false;

  void _setPressed(bool pressed) {
    widget.onPressChange?.call(pressed);
  }

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
        onShowHoverHighlight: (v) {
          setState(() => _hovered = v);
          widget.onHoverChange?.call(v);
        },
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onTap(),
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: content,
        ),
      ),
    );
  }
}
