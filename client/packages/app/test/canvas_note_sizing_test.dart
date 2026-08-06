// SPDX-License-Identifier: Apache-2.0
/// [noteBoxFor]: a note's placed box grows to fit its own text instead of
/// clipping inside a fixed one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/canvas/canvas_note_sizing.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart' show maxObjectExtent;

void main() {
  testWidgets('a short note keeps the fixed default box', (tester) async {
    final box = noteBoxFor('hello');
    expect(box.width, 220);
    expect(box.height, 140);
  });

  testWidgets('a longer note grows taller than the default, at the same '
      'width', (tester) async {
    final short = noteBoxFor('one short line');
    final long = noteBoxFor(List.filled(40, 'a whole sentence.').join(' '));

    expect(long.width, short.width, reason: 'width never grows for a note');
    expect(
      long.height,
      greaterThan(short.height),
      reason: 'height grows so the extra text is not clipped',
    );
  });

  testWidgets('height clamps at the object extent ceiling every other '
      'canvas object shares, rather than growing without bound', (
    tester,
  ) async {
    final box = noteBoxFor(List.filled(4000, 'word').join(' '));
    expect(box.height, maxObjectExtent);
  });

  testWidgets('empty text still answers the default box, never a zero one', (
    tester,
  ) async {
    final box = noteBoxFor('');
    expect(box.width, 220);
    expect(box.height, 140);
  });
}
