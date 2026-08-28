// SPDX-License-Identifier: Apache-2.0
/// Splitting an already-fence-free text run into structural markdown blocks:
/// headings, block quotes and lists. Each is recognised a whole line at a
/// time, since none of them can start except at the beginning of a line, and
/// this file has no opinion about inline formatting inside one: that is
/// layered on separately by whoever renders a block's text, so a heading or a
/// list item can still carry `**bold**` without this file knowing about it.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

sealed class MarkdownBlock {
  const MarkdownBlock();
}

class ParagraphBlock extends MarkdownBlock {
  const ParagraphBlock(this.text);
  final String text;
}

/// [level] is 1, 2 or 3 for `#`, `##`, `###`.
class HeadingBlock extends MarkdownBlock {
  const HeadingBlock(this.level, this.text);
  final int level;
  final String text;
}

class QuoteBlock extends MarkdownBlock {
  const QuoteBlock(this.text);
  final String text;
}

/// One list item. [depth] is 0 or 1: nesting goes one level by a two-space
/// indent, nothing deeper.
class ListItem {
  const ListItem(this.depth, this.text);
  final int depth;
  final String text;
}

class ListBlock extends MarkdownBlock {
  const ListBlock(this.ordered, this.items);
  final bool ordered;
  final List<ListItem> items;
}

final RegExp _heading = RegExp(r'^(#{1,3})[ \t]+(.*)$');

/// `(?:>[ \t]?)+` rather than one `>`: a forward of a forward requotes an
/// already-quoted line, stacking a `>` per hop (`buildForwardedContent` in
/// `forward_message.dart`). Stripping only the outermost one left every
/// deeper hop's marker sitting in the rendered text as a literal `>`
/// character; consuming every leading marker in one match flattens the
/// whole chain into a single quote box instead.
final RegExp _quote = RegExp(r'^(?:>[ \t]?)+(.*)$');
final RegExp _bullet = RegExp(r'^( {2})?[-*][ \t]+(.*)$');
final RegExp _ordered = RegExp(r'^( {2})?\d+\.[ \t]+(.*)$');

/// Splits [text] into the block elements above.
///
/// A run of lines with none of the leading markers becomes one
/// [ParagraphBlock], any blank lines inside it preserved exactly as before
/// this file existed: a plain message with no markdown at all still becomes
/// exactly one block holding the whole text, unchanged.
List<MarkdownBlock> splitMarkdownBlocks(String text) {
  final blocks = <MarkdownBlock>[];
  final paragraph = <String>[];
  final quote = <String>[];
  var listOrdered = false;
  final listItems = <ListItem>[];

  void flushParagraph() {
    if (paragraph.isNotEmpty) {
      final text = paragraph.join('\n');
      // A blank line between two other blocks lands here as an empty paragraph; drop it, not a real block.
      if (text.trim().isNotEmpty) blocks.add(ParagraphBlock(text));
      paragraph.clear();
    }
  }

  void flushQuote() {
    if (quote.isNotEmpty) {
      blocks.add(QuoteBlock(quote.join('\n')));
      quote.clear();
    }
  }

  void flushList() {
    if (listItems.isNotEmpty) {
      blocks.add(ListBlock(listOrdered, List.of(listItems)));
      listItems.clear();
    }
  }

  for (final line in text.split('\n')) {
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      flushQuote();
      flushList();
      blocks.add(HeadingBlock(heading.group(1)!.length, heading.group(2)!));
      continue;
    }

    final quoteMatch = _quote.firstMatch(line);
    if (quoteMatch != null) {
      flushParagraph();
      flushList();
      quote.add(quoteMatch.group(1)!);
      continue;
    }
    flushQuote();

    final bullet = _bullet.firstMatch(line);
    final ordered = _ordered.firstMatch(line);
    final item = ordered ?? bullet;
    if (item != null) {
      flushParagraph();
      final isOrdered = ordered != null;
      if (listItems.isNotEmpty && listOrdered != isOrdered) flushList();
      listOrdered = isOrdered;
      listItems.add(ListItem(item.group(1) != null ? 1 : 0, item.group(2)!));
      continue;
    }
    flushList();

    paragraph.add(line);
  }
  flushParagraph();
  flushQuote();
  flushList();
  return blocks;
}

/// A block quote: a left rule beside the quoted content, matching Discord's
/// own cue rather than inventing a new one.
class MarkdownQuote extends StatelessWidget {
  const MarkdownQuote({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      padding: const EdgeInsets.only(left: AppSpacing.s12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: tokens.borderSubtle, width: 3)),
      ),
      child: child,
    );
  }
}

/// One rendered list, bullet or ordered, with up to one level of nested
/// indent. [children] is already-built inline text per item, matching
/// [items] one for one; this widget only lays markers and indentation
/// around what it is handed.
class MarkdownList extends StatelessWidget {
  const MarkdownList({
    super.key,
    required this.ordered,
    required this.items,
    required this.children,
  });

  final bool ordered;
  final List<ListItem> items;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final markers = _markersFor(ordered, items);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(
              left: items[i].depth == 0 ? 0 : AppSpacing.s16,
              bottom: i == items.length - 1 ? 0 : AppSpacing.s4,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: AppSpacing.s20,
                  child: Text(
                    markers[i],
                    style: AppText.body.copyWith(color: tokens.textSecondary),
                  ),
                ),
                Expanded(child: children[i]),
              ],
            ),
          ),
      ],
    );
  }
}

/// One marker per item: a bullet glyph, or a number that restarts at each
/// depth-0 item, the way a nested sub-list normally counts.
List<String> _markersFor(bool ordered, List<ListItem> items) {
  final markers = <String>[];
  var topCount = 0;
  var nestedCount = 0;
  for (final item in items) {
    if (item.depth == 0) {
      topCount++;
      nestedCount = 0;
      markers.add(ordered ? '$topCount.' : '•');
    } else {
      nestedCount++;
      markers.add(ordered ? '$nestedCount.' : '–');
    }
  }
  return markers;
}
