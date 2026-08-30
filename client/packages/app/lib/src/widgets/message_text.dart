// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Rendering a message body: fenced code, headings, quotes, lists, inline
/// markdown, mentions, and the deployment's own `:shortcode:` emoji.
///
/// Inline nesting (`**bold with *italic* inside**`) comes from
/// `message_inline.dart`'s recursive-descent parser; this file walks its tree
/// into `InlineSpan`s and is where the two leaf tokens that need data
/// (mention, emoji) get resolved against what this message actually has.
///
/// There is no mention *highlighting* protocol on the wire; deciding whether
/// an `@name` token becomes a chip is a client-side judgement, applied to an
/// `@name` that matches a real, currently-known member's username, or to the
/// two reserved words `@everyone`/`@here` (`push::recipients` in
/// `crates/slimm-server`, gated there on `Perm.mentionEveryone` - rendering a
/// chip here does not imply the sender actually held it, only that the word
/// is one the server recognises). An `@` that matches neither renders as
/// plain text, so nothing here invents a person who is not real.
///
/// A `:shortcode:` resolves the same way and for the same reason: only a name
/// the deployment actually holds becomes an image, and everything else stays
/// the text that was typed.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import 'custom_emoji_image.dart';
import 'message_code_lexer.dart';
import 'message_fences.dart';
import 'message_inline.dart';
import 'message_markdown_blocks.dart';
import 'message_spoiler.dart';

/// One line tall: [AppText.body] is 15px at a 1.45 line height, so an inline
/// emoji is that product rather than a pixel value chosen to look right.
/// [CustomEmojiImage] defaults to the picker's 20; running text is not the
/// picker, so it says what it needs.
final double _emojiSize = AppText.body.fontSize! * AppText.body.height!;

/// A message body: fenced code blocks rendered through [AppCodeBlock], and
/// everything else split into headings, quotes, lists and paragraphs, each
/// carrying its own nested inline markdown. [knownUsernames] should be
/// lower-cased; pass an empty set while the member list has not loaded rather
/// than guessing.
class MessageBody extends StatelessWidget {
  const MessageBody({
    super.key,
    required this.content,
    required this.knownUsernames,
    this.customEmoji = const {},
    this.dim = false,
    this.announceSending = false,
  });

  final String content;
  final Set<String> knownUsernames;

  /// Lower-cased emoji name to emoji id, from `customEmojiIndexProvider`.
  /// Defaulted rather than required so a caller with no emoji to resolve
  /// (and every existing test) renders shortcodes as the plain text they are.
  final Map<String, String> customEmoji;

  /// True for a pending or failed send, which reads as provisional rather
  /// than delivered.
  final bool dim;

  /// True only while still sending: dims the same way [dim] does, and also
  /// gives the body a "Sending" semantics label, since [dim] on its own is a
  /// sighted-only cue - a screen reader reading this body's text got nothing
  /// distinguishing it from an already-delivered message. Deliberately not
  /// merged with [dim] itself: a caller dimming for some other reason
  /// (there is none today) must not also announce a delivery state that
  /// is not true.
  final bool announceSending;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    // Provisional-to-delivered ink lerps rather than snapping on confirm.
    final body = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: dim ? 1.0 : 0.0),
      duration: AppMotion.reduced(context, AppMotion.base),
      curve: AppMotion.entrance,
      builder: (context, t, _) {
        final baseColor = Color.lerp(
          tokens.textPrimary,
          tokens.textSecondary,
          t,
        )!;

        final widgets = <Widget>[];
        for (final block in splitMessageBlocks(content)) {
          switch (block) {
            case TextBlock(:final text):
              for (final md in splitMarkdownBlocks(text)) {
                widgets.add(
                  _buildMarkdownBlock(
                    md,
                    knownUsernames: knownUsernames,
                    customEmoji: customEmoji,
                    color: baseColor,
                  ),
                );
              }
            case CodeBlock(:final language, :final code):
              widgets.add(
                AppCodeBlock(
                  language: language,
                  lines: lexCodeBlock(code, language),
                ),
              );
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < widgets.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.s4),
              widgets[i],
            ],
          ],
        );
      },
    );

    // Its own container node: this body's several blocks already carry their own semantics, so a non-container label would have nowhere unambiguous to merge into.
    return announceSending
        ? Semantics(container: true, label: 'Sending', child: body)
        : body;
  }
}

/// Picks the type step and rendering shell for one [MarkdownBlock], then
/// hands its text to [_MessageTextRun] for inline parsing. Only headings
/// change the type style, from the scale's own three largest steps, never an
/// invented size.
Widget _buildMarkdownBlock(
  MarkdownBlock block, {
  required Set<String> knownUsernames,
  required Map<String, String> customEmoji,
  required Color color,
}) {
  switch (block) {
    case ParagraphBlock(:final text):
      return _MessageTextRun(
        text: text,
        knownUsernames: knownUsernames,
        customEmoji: customEmoji,
        color: color,
      );
    case HeadingBlock(:final level, :final text):
      final style = switch (level) {
        1 => AppText.title,
        2 => AppText.heading,
        _ => AppText.body,
      }.copyWith(fontWeight: AppWeights.semi);
      return _MessageTextRun(
        text: text,
        knownUsernames: knownUsernames,
        customEmoji: customEmoji,
        color: color,
        baseStyle: style,
      );
    case QuoteBlock(:final text):
      return MarkdownQuote(
        child: _MessageTextRun(
          text: text,
          knownUsernames: knownUsernames,
          customEmoji: customEmoji,
          color: color,
        ),
      );
    case ListBlock(:final ordered, :final items):
      return MarkdownList(
        ordered: ordered,
        items: items,
        children: [
          for (final item in items)
            _MessageTextRun(
              text: item.text,
              knownUsernames: knownUsernames,
              customEmoji: customEmoji,
              color: color,
            ),
        ],
      );
  }
}

/// One run of text with inline markdown, mentions and custom emoji picked
/// out. [baseStyle] carries size and weight; [color] is applied on top of it
/// so dimmed (pending/failed) messages still work at any heading level.
class _MessageTextRun extends StatelessWidget {
  const _MessageTextRun({
    required this.text,
    required this.knownUsernames,
    required this.customEmoji,
    required this.color,
    this.baseStyle = AppText.body,
  });

  final String text;
  final Set<String> knownUsernames;
  final Map<String, String> customEmoji;
  final Color color;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final style = baseStyle.copyWith(color: color);
    return Text.rich(
      TextSpan(
        style: style,
        children: _buildSpans(
          parseInline(text),
          knownUsernames,
          customEmoji,
          style,
        ),
      ),
    );
  }
}

/// The two reserved mentions `crates/slimm-server/src/push/recipients.rs`
/// resolves specially, never a real account (`validate_username` in
/// `http/auth.rs` refuses to register either, case-insensitively) - kept
/// lower-case, matched the same way against a lower-cased [raw].
const _reservedMentions = {'everyone', 'here'};

/// Whether [raw] (the whole `@name` token, `@` included) should render as a
/// chip: either it names someone in [knownUsernames], or it is one of the
/// two reserved words above. Rendering a reserved word as a chip says
/// nothing about whether the sender actually held `Perm.mentionEveryone` -
/// that permission only ever gates who gets woken for it, never whether the
/// word itself is recognised - so it is drawn the same way regardless.
bool _isRenderableMention(String raw, Set<String> knownUsernames) {
  final name = raw.substring(1).toLowerCase();
  return knownUsernames.contains(name) || _reservedMentions.contains(name);
}

/// Walks a [parseInline] tree into `InlineSpan`s. Bold, italic and
/// strikethrough are a style diff on a wrapping [TextSpan]; Flutter merges a
/// child span's style onto its parent's at paint time, which is the whole
/// mechanism nesting rides on: an [InlineBold] wrapping an [InlineItalic]
/// needs no combined style computed here, each node states only its own diff.
List<InlineSpan> _buildSpans(
  List<InlineNode> nodes,
  Set<String> knownUsernames,
  Map<String, String> customEmoji,
  TextStyle ambientStyle,
) => [
  for (final node in nodes)
    switch (node) {
      InlineText(:final text) => TextSpan(text: text),
      InlineCode(:final text) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: AppInlineCode(text),
      ),
      InlineMention(:final raw) =>
        _isRenderableMention(raw, knownUsernames)
            ? WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _MentionChip(raw),
              )
            : TextSpan(text: raw),
      InlineEmoji(:final raw) => _emojiSpan(raw, customEmoji),
      InlineBold(:final children) => TextSpan(
        style: const TextStyle(fontWeight: AppWeights.semi),
        children: _buildSpans(
          children,
          knownUsernames,
          customEmoji,
          ambientStyle,
        ),
      ),
      InlineItalic(:final children) => TextSpan(
        style: const TextStyle(fontStyle: FontStyle.italic),
        children: _buildSpans(
          children,
          knownUsernames,
          customEmoji,
          ambientStyle,
        ),
      ),
      InlineStrikethrough(:final children) => TextSpan(
        style: const TextStyle(decoration: TextDecoration.lineThrough),
        children: _buildSpans(
          children,
          knownUsernames,
          customEmoji,
          ambientStyle,
        ),
      ),
      InlineSpoiler(:final children) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: MessageSpoiler(
          style: ambientStyle,
          spans: _buildSpans(
            children,
            knownUsernames,
            customEmoji,
            ambientStyle,
          ),
        ),
      ),
    },
];

InlineSpan _emojiSpan(String raw, Map<String, String> customEmoji) {
  final id = customEmojiIdFor(raw, customEmoji);
  return id == null
      ? TextSpan(text: raw)
      : WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: CustomEmojiImage(emojiId: id, label: raw, size: _emojiSize),
        );
}

/// `--accent-text` on `--accent-soft`, matching the design's mention pill.
/// Not a design-system component: a mention is a message-body decoration
/// specific to this screen, not a control other surfaces reuse.
class _MentionChip extends StatelessWidget {
  const _MentionChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Text(
        text,
        style: AppText.body.copyWith(
          color: tokens.accent,
          fontWeight: AppWeights.medium,
        ),
      ),
    );
  }
}
