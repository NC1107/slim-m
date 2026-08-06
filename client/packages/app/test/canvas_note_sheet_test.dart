// SPDX-License-Identifier: Apache-2.0
/// The note sheet's byte-budget limiter.
///
/// The sheet used to cap input at a fixed character count (1800), on the
/// claim that stays under the server's 4 KiB `MAX_PROPS_BYTES` once wrapped
/// in `{"text":"..."}`. That claim was never tested against the real
/// escaping ratio: `serde_json` (server) and `jsonEncode` (here) both leave
/// non-ASCII bytes unescaped, so an ordinary CJK note - no hostile input
/// needed - already runs 3 bytes per character, and 1800 of them is 5,412
/// wire bytes, well past 4,096. This suite drives the real sheet with real
/// text and asserts what actually lands in the field never exceeds the
/// server's ceiling, rather than trusting a character count to imply it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/canvas/canvas_note_sheet.dart';
import 'package:slimm_design_system/design_system.dart';

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light, AppTokens.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCanvasNoteSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  test('noteWireBytes is the exact JSON-escaped, UTF-8 encoded wire cost', () {
    expect(noteWireBytes('a'), '{"text":"a"}'.length);
    // '中' is one UTF-16 code unit but three UTF-8 bytes, and serde_json
    // never escapes it: the wrapper is 11 fixed bytes (`{"text":""}`).
    expect(noteWireBytes('中'), 11 + 3);
    // A quote and a backslash each escape to two bytes.
    expect(noteWireBytes('"\\'), 11 + 4);
  });

  testWidgets(
    'a note filled entirely with plain ASCII up to the byte budget is accepted whole',
    (tester) async {
      await _open(tester);

      // The wrapper is 11 fixed bytes; the rest is all budget for content.
      final ascii = 'x' * (maxNoteTextBytes - 11);
      await tester.enterText(find.byType(TextField), ascii);
      await tester.pump();

      expect(
        _fieldText(tester),
        ascii,
        reason: 'text that exactly fits the budget must not be rejected',
      );
      expect(noteWireBytes(_fieldText(tester)), maxNoteTextBytes);
    },
  );

  testWidgets(
    'the client-legal 1800-character CJK note the server test reproduces '
    'never lands in the field at all',
    (tester) async {
      await _open(tester);

      // The exact string `a_note_at_the_clients_own_character_ceiling_can_'
      // 'still_be_refused_as_too_large` sends to the server: 1800 CJK
      // characters, 5,412 wire bytes once wrapped, refused there as a 400.
      await tester.enterText(find.byType(TextField), '中' * 1800);
      await tester.pump();

      expect(
        noteWireBytes(_fieldText(tester)),
        lessThanOrEqualTo(maxNoteTextBytes),
        reason:
            'an over-budget paste must never leave the field holding more '
            'than the server will accept',
      );
    },
  );

  testWidgets(
    'a single keystroke that would cross the budget is refused, keeping '
    'whatever already fit',
    (tester) async {
      await _open(tester);

      // Fill to exactly the CJK ceiling the byte budget allows (the fixed
      // `{"text":"..."}` wrapper costs 11 of those bytes), then try one more.
      final fits = '中' * ((maxNoteTextBytes - 11) ~/ 3);
      expect(noteWireBytes(fits), lessThanOrEqualTo(maxNoteTextBytes));
      await tester.enterText(find.byType(TextField), fits);
      await tester.pump();
      final before = _fieldText(tester);
      expect(noteWireBytes(before), lessThanOrEqualTo(maxNoteTextBytes));

      await tester.enterText(find.byType(TextField), '$before中');
      await tester.pump();

      expect(
        _fieldText(tester),
        before,
        reason: 'the one keystroke that would cross the budget must be refused whole',
      );
    },
  );
}
