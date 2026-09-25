// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A rail section's own header label and its "+" (split out of
/// `channel_rail_sections.dart` for the review budget): shared by
/// `DirectMessagesSection` and every channel category header.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import 'create_channel_sheet.dart';

class SectionLabel extends StatefulWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.trailingBuilder,
    this.chrome = true,
  });

  final String text;

  /// Builds the section's add glyph given whether it should currently show,
  /// and a callback to report the glyph's own focus back up to this header -
  /// null for a section nobody may add to. See [_SectionLabelState].
  final Widget Function(bool revealed, ValueChanged<bool> onFocusChange)?
  trailingBuilder;

  /// Whether [text] is this app's own wording rather than something someone
  /// typed. Chrome takes the uppercase treatment; a category name does not.
  ///
  /// The owner named the mismatch: they typed "dev" and "General", the
  /// categories screen showed them back exactly that way, and the rail
  /// showed "DEV" and "GENERAL". A name is the user's, and showing it in a
  /// case they did not choose is the app overruling them about their own
  /// data. The treatment stays where the words are ours.
  final bool chrome;

  @override
  State<SectionLabel> createState() => _SectionLabelState();
}

/// Mirrors `ManagedChannelRow`'s own hover/focus reveal for its kebab: a
/// pointer hovering the header reveals the trailing glyph, a keyboard
/// reaching it does too, and touch shows it always since a finger has no
/// hover. The header itself used to always show the glyph on the theory
/// that "a header has no hover state of its own" - true of the text, not of
/// the row it sits in, which can carry one exactly like a channel row does.
class _SectionLabelState extends State<SectionLabel> {
  bool _hovered = false;
  bool _trailingFocused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    if (widget.text.isEmpty) return const SizedBox.shrink();
    // Announced in its natural case: the uppercase is a visual treatment some screen readers would spell out.
    final label = Semantics(
      container: true,
      header: true,
      label: widget.text,
      child: ExcludeSemantics(
        child: Text(
          widget.chrome ? widget.text.toUpperCase() : widget.text,
          overflow: TextOverflow.ellipsis,
          style: AppText.label.copyWith(color: tokens.textSecondary),
        ),
      ),
    );
    final touch = AppTouchTargets.of(context);
    final revealed = touch || _hovered || _trailingFocused;
    final trailing = widget.trailingBuilder?.call(
      revealed,
      (v) => setState(() => _trailingFocused = v),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        // Mirrors AppListRow's horizontal padding, so header and row text share a left edge.
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s8,
          AppRhythm.headingTop,
          AppSpacing.s8,
          AppRhythm.headingBottom,
        ),
        child: trailing == null
            ? label
            : Row(
                children: [
                  Expanded(child: label),
                  trailing,
                ],
              ),
      ),
    );
  }
}

/// The `+` on a section header: makes a channel already filed under that
/// section, so nobody has to create one and immediately drag it.
///
/// Hover-revealed by [SectionLabel] the same way a row's kebab is; touch
/// always shows it, since this is the only pointer-free way to create a
/// channel in a specific place - a right-click has no touch equivalent. The
/// reveal wraps only the button, inside the alignment [Padding], the same
/// nesting `ManagedChannelRow`'s own kebab uses - wrapping the padding too
/// would merge it into the button's own semantics box and throw off the
/// shared right edge `category_add_channel_test.dart` measures.
class AddChannelGlyph extends StatelessWidget {
  const AddChannelGlyph({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.revealed,
    required this.onFocusChange,
  });

  /// Null for the implicit uncategorised section, which is what the create
  /// route already means by an absent category.
  final String? categoryId;
  final String categoryName;
  final bool revealed;
  final ValueChanged<bool> onFocusChange;

  @override
  Widget build(BuildContext context) {
    // The exact inset ChannelRow gives its kebab, from an edge already matching AppListRow's; both glyphs land on one line.
    final inset = AppTouchTargets.of(context) ? 0.0 : 4.0;
    return Padding(
      padding: EdgeInsets.only(right: inset),
      child: Focus(
        skipTraversal: true,
        canRequestFocus: false,
        onFocusChange: onFocusChange,
        child: AnimatedOpacity(
          opacity: revealed ? 1 : 0,
          duration: AppMotion.reduced(context, AppMotion.fast),
          // Hidden from the eye is not hidden from a screen reader.
          alwaysIncludeSemantics: true,
          child: AppIconButton(
            icon: AppIcons.add,
            semanticLabel: 'Create a channel in $categoryName',
            size: AppIconButtonSize.sm,
            onPressed: () => showCreateChannelSheet(
              context,
              initialKind: 'text',
              categoryId: categoryId,
            ),
          ),
        ),
      ),
    );
  }
}
