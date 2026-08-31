// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A hand-rolled recursive-descent parser for inline Discord-flavoured
/// markdown: `**bold**`, `*italic*`/`_italic_`, `~~strikethrough~~` and
/// `||spoiler||`, nesting inside one another, plus the three leaf tokens
/// `message_text.dart` already recognised: inline code, `@mention` and
/// `:shortcode:`.
///
/// Deliberately not the `markdown` or `flutter_markdown` package: both render
/// a whole document with their own theming and produce plain spans, never
/// the `WidgetSpan` mentions and custom-emoji images this client needs, so
/// hand-rolling the one grammar actually used is less code than fighting a
/// general-purpose renderer into emitting them. A single flat regex (the
/// shape `message_text.dart` used before this file existed) cannot express
/// nesting at all, which is why this is a parser rather than a bigger regex.
library;

/// One node of a parsed inline run. Leaves carry raw, unresolved text for the
/// two tokens whose meaning depends on data this file does not have
/// ([InlineMention] against a member list, [InlineEmoji] against a custom
/// emoji index); resolving them is `message_text.dart`'s job.
sealed class InlineNode {
  const InlineNode();
}

class InlineText extends InlineNode {
  const InlineText(this.text);
  final String text;
}

/// Raw content between a matched pair of backticks. Never itself parsed for
/// markdown, since code is quoted exactly as typed.
class InlineCode extends InlineNode {
  const InlineCode(this.text);
  final String text;
}

/// The raw `@name` token, including the `@`.
class InlineMention extends InlineNode {
  const InlineMention(this.raw);
  final String raw;
}

/// A role mention's name, brackets stripped and trimmed: `@[Core Team]`
/// parses to `Core Team`. Its own bracketed grammar rather than a widened
/// [InlineMention] charset, so a role name can hold spaces and mixed case,
/// and so a role and a user sharing a name are never ambiguous - `@nick` is
/// always [InlineMention], `@[nick]` is always this. Matched the identical
/// way in `mentioned_role_names` (`crates/slimm-server/src/push/
/// recipients.rs`).
class InlineRoleMention extends InlineNode {
  const InlineRoleMention(this.name);
  final String name;
}

/// The raw `:shortcode:` token, including both colons.
class InlineEmoji extends InlineNode {
  const InlineEmoji(this.raw);
  final String raw;
}

class InlineBold extends InlineNode {
  const InlineBold(this.children);
  final List<InlineNode> children;
}

class InlineItalic extends InlineNode {
  const InlineItalic(this.children);
  final List<InlineNode> children;
}

class InlineStrikethrough extends InlineNode {
  const InlineStrikethrough(this.children);
  final List<InlineNode> children;
}

class InlineSpoiler extends InlineNode {
  const InlineSpoiler(this.children);
  final List<InlineNode> children;
}

/// A mention's charset, greedy: the first character must be a word
/// character, and `.`/`-` are accepted as interior separators alongside the
/// rest, matching what `validate_username` (`crates/slimm-server/src/http/
/// auth.rs`) allows a real account to be named. The greedy match is trimmed
/// of trailing `.`/`-` by [_trimMentionEnd] below, since a username cannot
/// be told apart from sentence punctuation by charset alone.
final RegExp _mentionPattern = RegExp(r'@[A-Za-z0-9_][A-Za-z0-9_.-]*');
final RegExp _emojiPattern = RegExp(r':[A-Za-z0-9_]{1,32}:');
final RegExp _digitsOnly = RegExp(r'^[0-9]+$');
final RegExp _wordChar = RegExp(r'[A-Za-z0-9_]');

bool _isWordAt(String s, int i) =>
    i >= 0 && i < s.length && _wordChar.hasMatch(s[i]);

/// Whitespace, or off either end of the string: both count as a boundary a
/// delimiter cannot open or close against.
bool _isBoundary(String s, int i) =>
    i < 0 || i >= s.length || s[i] == ' ' || s[i] == '\t' || s[i] == '\n';

bool _isDigit(String s, int i) {
  final unit = s.codeUnitAt(i);
  return unit >= 0x30 && unit <= 0x39;
}

/// A name made only of digits reads as part of a clock time when a digit sits
/// against either colon (`10:30:45`), the same rule `message_text.dart` used
/// to apply directly; moved here since this is now where `:shortcode:` is
/// first recognised.
bool _readsAsDigitRun(String s, int start, int end) {
  final inner = s.substring(start + 1, end - 1);
  if (!_digitsOnly.hasMatch(inner)) return false;
  final before = start - 1;
  return (before >= 0 && _isDigit(s, before)) ||
      (end < s.length && _isDigit(s, end));
}

/// Trims trailing `.`/`-` off a greedy `[start, end)` mention match, so
/// `@nick.` at the end of a sentence keeps the full stop out of the name.
/// `start` is the `@`, so `start + 2` is the first index that may never be
/// stripped: the character right after `@` is always a word character by
/// [_mentionPattern]'s own anchor, and this loop never removes it. The cost:
/// a username genuinely ending in `.` or `-` can never be mentioned, since
/// its trailing character reads as punctuation instead. Kept in sync with
/// `mentioned_usernames` in `crates/slimm-server/src/push/recipients.rs`,
/// which strips the same way over the same charset.
int _trimMentionEnd(String s, int start, int end) {
  while (end > start + 2 && (s[end - 1] == '.' || s[end - 1] == '-')) {
    end--;
  }
  return end;
}

/// The index just past the closing `]` of an `@[Name]` role mention opening
/// at [start] (where `s[start] == '@'` and `s[start + 1] == '['`), or -1
/// when there is no `]` before a newline or the end of the string - matched
/// the identical way `mentioned_role_names` in `crates/slimm-server/src/
/// push/recipients.rs` scans the same grammar.
int _roleMentionEnd(String s, int start) {
  final from = start + 2;
  for (var j = from; j < s.length; j++) {
    if (s[j] == '\n') return -1;
    if (s[j] == ']') return j + 1;
  }
  return -1;
}

/// The index just past a backtick-delimited code span starting at [start]
/// (where `s[start] == '`'`), or -1 when there is no closing backtick before
/// a newline: inline code never crosses one, since it is a short run.
int _codeSpanEnd(String s, int start) {
  var j = start + 1;
  while (j < s.length && s[j] != '`' && s[j] != '\n') {
    j++;
  }
  return (j < s.length && s[j] == '`' && j > start + 1) ? j : -1;
}

/// Scans forward from [from] for the literal [closer], skipping over any
/// inline code span whole so a fence character inside code is never mistaken
/// for a markdown delimiter.
int _findCloser(String s, int from, String closer) {
  var j = from;
  while (j <= s.length - closer.length) {
    if (s[j] == '`') {
      final end = _codeSpanEnd(s, j);
      j = end == -1 ? j + 1 : end + 1;
      continue;
    }
    if (s.substring(j, j + closer.length) == closer) return j;
    j++;
  }
  return -1;
}

/// A lone `*` closer: not adjacent to another `*` on either side (which
/// would make it part of a `**` pair instead), and not preceded by
/// whitespace, which is what keeps `2 * 3` from closing on its own space.
int _findItalicStarCloser(String s, int from) {
  var j = from;
  while (j < s.length) {
    if (s[j] == '`') {
      final end = _codeSpanEnd(s, j);
      j = end == -1 ? j + 1 : end + 1;
      continue;
    }
    if (s[j] == '*' &&
        (j == 0 || s[j - 1] != '*') &&
        (j + 1 >= s.length || s[j + 1] != '*') &&
        !_isBoundary(s, j - 1)) {
      return j;
    }
    j++;
  }
  return -1;
}

/// A `_` closer: not preceded by whitespace and not followed by a word
/// character, which is what keeps `snake_case_name` from closing mid-word.
int _findItalicUnderscoreCloser(String s, int from) {
  var j = from;
  while (j < s.length) {
    if (s[j] == '`') {
      final end = _codeSpanEnd(s, j);
      j = end == -1 ? j + 1 : end + 1;
      continue;
    }
    if (s[j] == '_' && !_isBoundary(s, j - 1) && !_isWordAt(s, j + 1)) {
      return j;
    }
    j++;
  }
  return -1;
}

/// Parses [content] into a tree of [InlineNode]s.
///
/// A delimiter pair nests by recursing over the substring between an opener
/// and its matched closer, which is what lets `**bold with *italic* inside**`
/// parse as a bold run containing an italic run: something no flat regex can
/// express. An opener with no matching closer anywhere after it is not a
/// delimiter at all and is left as the literal character it was typed as.
List<InlineNode> parseInline(String content) {
  final nodes = <InlineNode>[];
  final buffer = StringBuffer();
  var i = 0;

  void flush() {
    if (buffer.isNotEmpty) {
      nodes.add(InlineText(buffer.toString()));
      buffer.clear();
    }
  }

  while (i < content.length) {
    final ch = content[i];

    if (ch == '`') {
      final end = _codeSpanEnd(content, i);
      if (end != -1) {
        flush();
        nodes.add(InlineCode(content.substring(i + 1, end)));
        i = end + 1;
        continue;
      }
    } else if (ch == '*' && i + 1 < content.length && content[i + 1] == '*') {
      final close = _findCloser(content, i + 2, '**');
      if (close != -1) {
        flush();
        nodes.add(InlineBold(parseInline(content.substring(i + 2, close))));
        i = close + 2;
        continue;
      }
    } else if (ch == '~' && i + 1 < content.length && content[i + 1] == '~') {
      final close = _findCloser(content, i + 2, '~~');
      if (close != -1) {
        flush();
        nodes.add(
          InlineStrikethrough(parseInline(content.substring(i + 2, close))),
        );
        i = close + 2;
        continue;
      }
    } else if (ch == '|' && i + 1 < content.length && content[i + 1] == '|') {
      final close = _findCloser(content, i + 2, '||');
      if (close != -1) {
        flush();
        nodes.add(InlineSpoiler(parseInline(content.substring(i + 2, close))));
        i = close + 2;
        continue;
      }
    } else if (ch == '*') {
      if (!_isBoundary(content, i + 1)) {
        final close = _findItalicStarCloser(content, i + 1);
        if (close != -1) {
          flush();
          nodes.add(InlineItalic(parseInline(content.substring(i + 1, close))));
          i = close + 1;
          continue;
        }
      }
    } else if (ch == '_') {
      if (!_isWordAt(content, i - 1) && !_isBoundary(content, i + 1)) {
        final close = _findItalicUnderscoreCloser(content, i + 1);
        if (close != -1) {
          flush();
          nodes.add(InlineItalic(parseInline(content.substring(i + 1, close))));
          i = close + 1;
          continue;
        }
      }
    } else if (ch == '@') {
      if (i + 1 < content.length && content[i + 1] == '[') {
        final end = _roleMentionEnd(content, i);
        if (end != -1) {
          final name = content.substring(i + 2, end - 1).trim();
          if (name.isNotEmpty) {
            flush();
            nodes.add(InlineRoleMention(name));
            i = end;
            continue;
          }
        }
      }
      final m = _mentionPattern.matchAsPrefix(content, i);
      if (m != null) {
        final end = _trimMentionEnd(content, i, m.end);
        flush();
        nodes.add(InlineMention(content.substring(i, end)));
        i = end;
        continue;
      }
    } else if (ch == ':') {
      final m = _emojiPattern.matchAsPrefix(content, i);
      if (m != null && !_readsAsDigitRun(content, m.start, m.end)) {
        flush();
        nodes.add(InlineEmoji(m.group(0)!));
        i = m.end;
        continue;
      }
    }

    buffer.write(ch);
    i++;
  }

  flush();
  return nodes;
}
