// SPDX-License-Identifier: Apache-2.0
/// Blanks `//` and `/* */` comments and `'...'`/`"..."` string-literal
/// content to spaces, keeping every character's index (and every newline)
/// exactly where it was, so a source-reading gate's regex or brace count
/// only ever sees real code.
///
/// `route_reachability_test.dart` used to strip only a *whole-line* `//`
/// comment before searching for a route's real usage, and its own doc
/// comment already tells the story of that test "catching itself passing
/// on the comment above the very button it was written to protect" - but
/// the fix that followed left a trailing `//` comment and any `/* */`
/// block comment unstripped. Reproduced directly: replacing a route's only
/// real navigation call with a *different* route, then leaving a trailing
/// `// was Routes.adminAnalytics before a rename` comment on that same
/// line, still passed the gate - the exact shape the test's own history
/// already names, recurring through the one path its fix never covered.
/// `settings_frame_inset_test.dart` had an independent instance of the
/// same class: a stray unmatched `)` inside a `//` comment - a smiley
/// face, "ok :)", is enough - closed its balanced-paren scan early and hid
/// a genuine `padding:` argument sitting after it.
library;

String codeOnly(String source) {
  final out = StringBuffer();
  var i = 0;
  String? quote;
  while (i < source.length) {
    final c = source[i];
    if (quote != null) {
      if (c == r'\' && i + 1 < source.length) {
        out.write(' ');
        i++;
        out.write(source[i] == '\n' ? '\n' : ' ');
        i++;
        continue;
      }
      out.write(c == '\n' ? '\n' : ' ');
      if (c == quote) quote = null;
      i++;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      out.write(' ');
      i++;
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      final end = source.indexOf('\n', i);
      final stop = end == -1 ? source.length : end;
      out.write(' ' * (stop - i));
      i = stop;
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
      final end = source.indexOf('*/', i + 2);
      final stop = end == -1 ? source.length : end + 2;
      for (var j = i; j < stop; j++) {
        out.write(source[j] == '\n' ? '\n' : ' ');
      }
      i = stop;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}
