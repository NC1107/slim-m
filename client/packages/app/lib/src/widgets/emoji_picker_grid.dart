// SPDX-License-Identifier: Apache-2.0
/// The emoji picker's category tab row and result grid.
library;

import 'package:emojis/emoji.dart';
import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

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

/// A fixed-column grid of [emoji], with [highlighted] drawing the one
/// keyboard `ArrowUp`/`ArrowDown` navigation currently sits on. Own scroll
/// view: the panel gives it a bounded height and lets it page internally.
class EmojiGrid extends StatelessWidget {
  const EmojiGrid({
    super.key,
    required this.emoji,
    required this.highlighted,
    required this.onTap,
  });

  final List<Emoji> emoji;
  final int highlighted;
  final ValueChanged<Emoji> onTap;

  static const int columns = 8;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.s8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
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

  final Emoji emoji;
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
      // 20, not on AppText's scale: sized to read as a legible glyph rather
      // than any text style, the same literal exception AppChip.reaction
      // documents for its own emoji glyph.
      child: Text(
        widget.emoji.char,
        style: const TextStyle(fontSize: 20, height: 1),
      ),
    );

    return Semantics(
      label: widget.emoji.name,
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
