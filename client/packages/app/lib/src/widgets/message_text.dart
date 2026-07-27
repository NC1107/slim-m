// SPDX-License-Identifier: Apache-2.0
/// Rendering a message body: fenced code, plain text, inline code, and
/// mentions.
///
/// There is no mention protocol on the wire (no server-side highlighting or
/// notification hook); this is a client-side decoration only, so it is only
/// ever applied to an `@name` token that matches a real, currently-known
/// member's username. An `@` that does not match one renders as plain text
/// rather than a mention, so nothing here invents a person who is not real.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import 'message_code_lexer.dart';
import 'message_fences.dart';

/// Matches a backtick-fenced inline code run or an `@username` token. Neither
/// crosses a newline, since both are meant to be short inline runs.
final RegExp _inlineTokenPattern = RegExp(r'`[^`\n]+`|@[A-Za-z0-9_]+');

enum _SpanKind { text, code, mention }

class _Token {
  const _Token(this.kind, this.text);
  final _SpanKind kind;
  final String text;
}

List<_Token> _tokenize(String content, Set<String> knownUsernames) {
  final tokens = <_Token>[];
  var last = 0;
  for (final match in _inlineTokenPattern.allMatches(content)) {
    if (match.start > last) {
      tokens.add(_Token(_SpanKind.text, content.substring(last, match.start)));
    }
    final raw = match.group(0)!;
    if (raw.startsWith('`')) {
      tokens.add(_Token(_SpanKind.code, raw.substring(1, raw.length - 1)));
    } else if (knownUsernames.contains(raw.substring(1).toLowerCase())) {
      tokens.add(_Token(_SpanKind.mention, raw));
    } else {
      tokens.add(_Token(_SpanKind.text, raw));
    }
    last = match.end;
  }
  if (last < content.length) {
    tokens.add(_Token(_SpanKind.text, content.substring(last)));
  }
  return tokens;
}

/// A message body: fenced code blocks rendered through [AppCodeBlock], and
/// everything else through the inline code/mention tokenizer.
/// [knownUsernames] should be lower-cased; pass an empty set while the
/// member list has not loaded rather than guessing.
class MessageBody extends StatelessWidget {
  const MessageBody({
    super.key,
    required this.content,
    required this.knownUsernames,
    this.dim = false,
  });

  final String content;
  final Set<String> knownUsernames;

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

/// One [TextBlock]'s worth of running text, with inline code and mentions
/// picked out.
class _MessageTextRun extends StatelessWidget {
  const _MessageTextRun({
    required this.text,
    required this.knownUsernames,
    required this.color,
  });

  final String text;
  final Set<String> knownUsernames;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: AppText.body.copyWith(color: color),
        children: [
          for (final token in _tokenize(text, knownUsernames))
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
