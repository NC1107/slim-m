// SPDX-License-Identifier: Apache-2.0
/// Rendering a message body: fenced code, plain text, inline code, mentions,
/// and the deployment's own `:shortcode:` emoji.
///
/// There is no mention protocol on the wire (no server-side highlighting or
/// notification hook); this is a client-side decoration only, so it is only
/// ever applied to an `@name` token that matches a real, currently-known
/// member's username. An `@` that does not match one renders as plain text
/// rather than a mention, so nothing here invents a person who is not real.
///
/// A `:shortcode:` resolves the same way and for the same reason: only a name
/// the deployment actually holds becomes an image, and everything else stays
/// the text that was typed. Colons are ordinary punctuation, so `10:30:45`
/// must survive this file untouched, which takes one rule beyond "is it a
/// name we hold": see [_readsAsDigitRun].
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import 'custom_emoji_image.dart';
import 'message_code_lexer.dart';
import 'message_fences.dart';

/// Matches a backtick-fenced inline code run, an `@username` token, or a
/// `:shortcode:`. None crosses a newline, since all are short inline runs.
///
/// The shortcode's 32-character ceiling is `MAX_NAME_LEN`
/// (`crates/slimm-server/src/emoji.rs:24`): a longer run cannot name an emoji
/// that exists, so there is no point scanning it as one.
final RegExp _inlineTokenPattern = RegExp(
  r'`[^`\n]+`|@[A-Za-z0-9_]+|:[A-Za-z0-9_]{1,32}:',
);

/// A name made only of digits, which the server's charset (a-z, 0-9, `_`)
/// allows: `:30:` is a legal emoji and also two thirds of a clock time.
final RegExp _digitsOnlyName = RegExp(r'^[0-9]+$');

/// Whether the `:shortcode:` [match] found in [content] is really part of a
/// run of digits, as the `:30:` in `10:30:45` is.
///
/// Refusing every digits-only name would be simpler and worse: an emoji named
/// `100` would then be uploadable, offered by the picker, inserted into the
/// composer and unrenderable forever, which is a dead feature rather than a
/// fixed bug. The ambiguity is only ever a digit pressed against one of the
/// colons, so that is all this refuses, and `:100:` in prose still resolves.
bool _readsAsDigitRun(String content, RegExpMatch match) {
  final raw = match.group(0)!;
  if (!_digitsOnlyName.hasMatch(raw.substring(1, raw.length - 1))) return false;
  return _isDigitAt(content, match.start - 1) || _isDigitAt(content, match.end);
}

bool _isDigitAt(String content, int index) {
  if (index < 0 || index >= content.length) return false;
  final unit = content.codeUnitAt(index);
  return unit >= 0x30 && unit <= 0x39;
}

/// One line tall: [AppText.body] is 15px at a 1.45 line height, so an inline
/// emoji is that product rather than a pixel value chosen to look right.
/// [CustomEmojiImage] defaults to the picker's 20; running text is not the
/// picker, so it says what it needs.
final double _emojiSize = AppText.body.fontSize! * AppText.body.height!;

enum _SpanKind { text, code, mention, emoji }

class _Token {
  const _Token(this.kind, this.text, {this.emojiId});
  final _SpanKind kind;
  final String text;

  /// Set only on [_SpanKind.emoji]: which of the deployment's emoji [text]
  /// resolved to.
  final String? emojiId;
}

/// [customEmoji] maps a lower-cased emoji name to its id; an empty map (the
/// set has not loaded, or failed to) resolves nothing, which leaves every
/// shortcode as the literal text it already was.
List<_Token> _tokenize(
  String content,
  Set<String> knownUsernames,
  Map<String, String> customEmoji,
) {
  final tokens = <_Token>[];
  var last = 0;
  for (final match in _inlineTokenPattern.allMatches(content)) {
    if (match.start > last) {
      tokens.add(_Token(_SpanKind.text, content.substring(last, match.start)));
    }
    final raw = match.group(0)!;
    if (raw.startsWith('`')) {
      tokens.add(_Token(_SpanKind.code, raw.substring(1, raw.length - 1)));
    } else if (raw.startsWith('@')) {
      tokens.add(
        knownUsernames.contains(raw.substring(1).toLowerCase())
            ? _Token(_SpanKind.mention, raw)
            : _Token(_SpanKind.text, raw),
      );
    } else {
      final id = _readsAsDigitRun(content, match)
          ? null
          : customEmojiIdFor(raw, customEmoji);
      tokens.add(
        id == null
            ? _Token(_SpanKind.text, raw)
            : _Token(_SpanKind.emoji, raw, emojiId: id),
      );
    }
    last = match.end;
  }
  if (last < content.length) {
    tokens.add(_Token(_SpanKind.text, content.substring(last)));
  }
  return tokens;
}

/// A message body: fenced code blocks rendered through [AppCodeBlock], and
/// everything else through the inline code/mention/emoji tokenizer.
/// [knownUsernames] should be lower-cased; pass an empty set while the
/// member list has not loaded rather than guessing.
class MessageBody extends StatelessWidget {
  const MessageBody({
    super.key,
    required this.content,
    required this.knownUsernames,
    this.customEmoji = const {},
    this.dim = false,
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

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final baseColor = dim ? tokens.textSecondary : tokens.textPrimary;
    final blocks = splitMessageBlocks(content);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s4),
          switch (blocks[i]) {
            TextBlock(:final text) => _MessageTextRun(
              text: text,
              knownUsernames: knownUsernames,
              customEmoji: customEmoji,
              color: baseColor,
            ),
            CodeBlock(:final language, :final code) => AppCodeBlock(
              language: language,
              lines: lexCodeBlock(code, language),
            ),
          },
        ],
      ],
    );
  }
}

/// One [TextBlock]'s worth of running text, with inline code, mentions and
/// custom emoji picked out.
class _MessageTextRun extends StatelessWidget {
  const _MessageTextRun({
    required this.text,
    required this.knownUsernames,
    required this.customEmoji,
    required this.color,
  });

  final String text;
  final Set<String> knownUsernames;
  final Map<String, String> customEmoji;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: AppText.body.copyWith(color: color),
        children: [
          for (final token in _tokenize(text, knownUsernames, customEmoji))
            switch (token.kind) {
              _SpanKind.text => TextSpan(text: token.text),
              _SpanKind.code => WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: AppInlineCode(token.text),
              ),
              _SpanKind.mention => WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _MentionChip(token.text),
              ),
              _SpanKind.emoji => WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: CustomEmojiImage(
                  emojiId: token.emojiId!,
                  label: token.text,
                  size: _emojiSize,
                ),
              ),
            },
        ],
      ),
    );
  }
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
