// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Making a code block's invisible characters visible.
///
/// A text-direction or zero-width character changes what a reader sees
/// without changing what runs (trojan source, CVE-2021-42574). The block
/// keeps its bytes; the rendering swaps each such character for a named
/// marker such as `<U+202E>`, and the Run affordance is withheld while any
/// is present. The set mirrors the server's own refusal in `code_runs.rs`.
library;

import 'package:slimm_design_system/design_system.dart';

bool isHiddenCodeCharacter(int c) {
  if (c == 0x09 || c == 0x0A || c == 0x0D) return false;
  return c < 0x20 ||
      (c >= 0x7F && c <= 0x9F) ||
      c == 0x061C ||
      (c >= 0x200B && c <= 0x200F) ||
      (c >= 0x202A && c <= 0x202E) ||
      c == 0x2060 ||
      (c >= 0x2066 && c <= 0x2069) ||
      c == 0xFEFF;
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
