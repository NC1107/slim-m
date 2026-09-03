// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Whether a message mentions a given username, for anything that needs the
/// answer as a plain bool rather than as rendered chips - today, deciding a
/// `mention` notification chime apart from an ordinary `group_message` one.
/// Split out of `message_inline.dart` to keep that file under this repo's
/// review budget.
library;

import 'message_inline.dart';

/// Whether [content] mentions [username], case-insensitively - walked
/// through the real [parseInline] tree rather than re-run as a bare regex,
/// so a mention nested inside bold, italic, strikethrough or a spoiler is
/// still found the same way the transcript itself would render it.
bool messageMentionsUsername(String content, String username) {
  if (username.isEmpty) return false;
  final target = username.toLowerCase();

  bool walk(List<InlineNode> nodes) {
    for (final node in nodes) {
      switch (node) {
        case InlineMention(:final raw):
          if (raw.substring(1).toLowerCase() == target) return true;
        case InlineBold(:final children):
        case InlineItalic(:final children):
        case InlineStrikethrough(:final children):
        case InlineSpoiler(:final children):
          if (walk(children)) return true;
        case InlineText():
        case InlineCode():
        case InlineEmoji():
        case InlineRoleMention():
        case InlineLink():
          break;
      }
    }
    return false;
  }

  return walk(parseInline(content));
}
