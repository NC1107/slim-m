// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Making a code block's invisible characters visible.
///
/// A text-direction or zero-width character changes what a reader sees
/// without changing what runs (trojan source, CVE-2021-42574). The block
/// keeps its bytes; the rendering swaps each such character for a named
/// marker such as `<U+202E>`, and the Run affordance is withheld while any
/// is present. The set is the server's own refusal, `isHiddenCodeCharacter` below.
library;

import 'package:slimm_design_system/design_system.dart';

/// Mirrors `is_hidden_char` in the server's `hidden_chars.rs`; both are held to
/// `crates/slimm-server/tests/fixtures/hidden_chars.json`. Tab, line feed and
/// carriage return are layout inside a code block, so they are the one exemption.
bool isHiddenCodeCharacter(int c) {
  if (c == 0x09 || c == 0x0A || c == 0x0D) return false;
  return c < 0x20 ||
      (c >= 0x7F && c <= 0x9F) ||
      c == 0x00AD ||
      c == 0x034F ||
      c == 0x061C ||
      (c >= 0x115F && c <= 0x1160) ||
      (c >= 0x17B4 && c <= 0x17B5) ||
      c == 0x180E ||
      (c >= 0x200B && c <= 0x200F) ||
      (c >= 0x2028 && c <= 0x202E) ||
      (c >= 0x2060 && c <= 0x206F) ||
      c == 0x2800 ||
      c == 0x3164 ||
      c == 0xFEFF ||
      c == 0xFFA0 ||
      (c >= 0xFFF9 && c <= 0xFFFC) ||
      (c >= 0xE0000 && c <= 0xE007F);
}

bool hasHiddenCodeCharacters(String code) =>
    code.runes.any(isHiddenCodeCharacter);

String _marker(int c) =>
    '<U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')}>';

/// [lines] with every hidden character replaced by its marker, in a span of
/// its own so the surrounding roles are kept.
List<AppCodeLine> revealHiddenCodeCharacters(List<AppCodeLine> lines) => [
  for (final line in lines)
    AppCodeLine([for (final span in line.spans) ..._reveal(span)]),
];

Iterable<AppCodeSpan> _reveal(AppCodeSpan span) sync* {
  if (!hasHiddenCodeCharacters(span.text)) {
    yield span;
    return;
  }
  final plain = StringBuffer();
  for (final c in span.text.runes) {
    if (!isHiddenCodeCharacter(c)) {
      plain.writeCharCode(c);
      continue;
    }
    if (plain.isNotEmpty) {
      yield AppCodeSpan(plain.toString(), span.role);
      plain.clear();
    }
    yield AppCodeSpan(_marker(c), AppCodeRole.hidden);
  }
  if (plain.isNotEmpty) yield AppCodeSpan(plain.toString(), span.role);
}
