// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// One-line previews of a message's text, for quotes and banners.
library;

final _fence = RegExp(r'```[\s\S]*?(?:```|$)');
final _inlineCode = RegExp(r'`([^`\n]+)`');
final _whitespace = RegExp(r'\s+');

/// [content] flattened to one line of plain text: a fenced code block becomes
/// "[code]" and inline code loses its backticks. Empty when nothing is left.
String plainPreview(String content) {
  final withoutFences = content.replaceAll(_fence, ' [code] ');
  final withoutTicks = withoutFences.replaceAllMapped(
    _inlineCode,
    (m) => m[1]!,
  );
  return withoutTicks.replaceAll(_whitespace, ' ').trim();
}

/// [plainPreview] cut to [maxRunes] runes, or "(no text)" when it is empty.
/// Rune-safe: `String.substring` cuts mid-surrogate outside the BMP.
String previewSnippet(String content, {required int maxRunes}) {
  final oneLine = plainPreview(content);
  if (oneLine.isEmpty) return '(no text)';
  final runes = oneLine.runes.toList(growable: false);
  if (runes.length <= maxRunes) return oneLine;
  return '${String.fromCharCodes(runes.take(maxRunes))}…';
}
