// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Composer affordances for typing markdown by hand: continuing a list on
/// Enter, and Ctrl/Cmd+B and Ctrl/Cmd+I wrapping the current selection.
///
/// Split out of `composer.dart` (already near its own line budget) and kept
/// as pure functions over a [TextEditingValue] rather than methods on the
/// composer's state, so each is testable without building a widget tree.
library;

import 'package:flutter/material.dart';

final RegExp _bulletLine = RegExp(r'^( {0,2})([-*])[ \t]+(.*)$');
final RegExp _orderedLine = RegExp(r'^( {0,2})(\d+)\.[ \t]+(.*)$');

/// What continuing a list looks like after Enter at [value]'s caret, or null
/// when the current line is not a list item at all (an ordinary newline
/// applies instead).
///
/// An empty item (just a marker, nothing typed after it) ends the list
/// rather than continuing it: without this, pressing Enter twice to finish a
/// list would instead type the marker forever.
TextEditingValue? continueList(TextEditingValue value) {
  if (!value.selection.isCollapsed) return null;
  final caret = value.selection.baseOffset;
  if (caret < 0) return null;
  final text = value.text;
  final lineStart = text.lastIndexOf('\n', caret - 1) + 1;
  final line = text.substring(lineStart, caret);

  final ordered = _orderedLine.firstMatch(line);
  final bullet = ordered == null ? _bulletLine.firstMatch(line) : null;
  final match = ordered ?? bullet;
  if (match == null) return null;

  final indent = match.group(1)!;
  final content = match.group(3)!;

  if (content.trim().isEmpty) {
    return TextEditingValue(
      text: text.replaceRange(lineStart, caret, ''),
      selection: TextSelection.collapsed(offset: lineStart),
    );
  }

  final nextMarker = ordered != null
      ? '${int.parse(ordered.group(2)!) + 1}.'
      : match.group(2)!;
  final insertion = '\n$indent$nextMarker ';
  return TextEditingValue(
    text: text.replaceRange(caret, caret, insertion),
    selection: TextSelection.collapsed(offset: caret + insertion.length),
  );
}

/// Enter's whole effect on [value]: continue or end a list, or otherwise
/// insert the plain newline a hardware Enter key would have. Intercepting the
/// key to check for a list also pre-empts the field's own default handling,
/// so the plain-newline case has to be produced here rather than falling
/// through to it.
TextEditingValue applyListAwareEnter(TextEditingValue value) {
  final continued = continueList(value);
  if (continued != null) return continued;
  final selection = value.selection;
  final start = selection.start < 0 ? value.text.length : selection.start;
  final end = selection.end < 0 ? value.text.length : selection.end;
  return TextEditingValue(
    text: value.text.replaceRange(start, end, '\n'),
    selection: TextSelection.collapsed(offset: start + 1),
  );
}

/// Wraps the current selection in [marker] on both sides (`**` for bold,
/// `*` for italic), or inserts an empty pair with the caret left between
/// them when nothing is selected, so typing continues inside the markers.
TextEditingValue wrapSelectionWithMarker(
  TextEditingValue value,
  String marker,
) {
  final selection = value.selection;
  final start = selection.start < 0 ? value.text.length : selection.start;
  final end = selection.end < 0 ? value.text.length : selection.end;
  final selected = value.text.substring(start, end);
  final text = value.text.replaceRange(start, end, '$marker$selected$marker');
  final newSelection = selected.isEmpty
      ? TextSelection.collapsed(offset: start + marker.length)
      : TextSelection(
          baseOffset: start + marker.length,
          extentOffset: start + marker.length + selected.length,
        );
  return TextEditingValue(text: text, selection: newSelection);
}
