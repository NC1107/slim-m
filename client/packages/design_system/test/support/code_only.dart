// SPDX-License-Identifier: Apache-2.0
/// Blanks `//` and `/* */` comments and `'...'`/`"..."` string-literal
/// content to spaces, keeping every character's index (and every newline)
/// exactly where it was, so a source-reading gate's regex or count only
/// ever sees real code.
///
/// `reduce_motion_gate_test.dart` compares a per-file *count* of a call
/// pattern against a count of the override phrase that must accompany it -
/// and a plain `// TODO: this should carry animationStyle:
/// AnimationStyle.noAnimation` comment sitting anywhere in the same file
/// inflates the override count enough to mask a real `showDialog(...)`
/// call carrying no override at all. Reproduced directly before this
/// existed: a genuine violation plus that one comment line passed the
/// gate silently. `app/test/support/code_only.dart` carries the identical
/// implementation and the same finding for `route_reachability_test.dart`
/// and `settings_frame_inset_test.dart`; duplicated here rather than
/// shared, since a package's `test/` directory is not importable across
/// package boundaries the way its `lib/` is.
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
