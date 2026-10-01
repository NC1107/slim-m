// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A quote of a message shows its text, never the markdown that formats it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/message_preview.dart';
import 'package:slimm_app/src/widgets/reply_quote.dart';

import 'message_row_harness.dart';

const _fenced =
    'Here is the snippet I mean:\n```dart\nclass Rail extends StatelessWidget {}\n```';

void main() {
  group('plainPreview', () {
    test('collapses a fenced block to a code marker', () {
      expect(plainPreview(_fenced), 'Here is the snippet I mean: [code]');
    });

    test('a message that opens with a fence reads as code', () {
      expect(
        plainPreview('```\nlet x = 1;\n```\nthen this'),
        '[code] then this',
      );
    });

    test('an unterminated fence does not leak its backticks', () {
      expect(plainPreview('look:\n```dart\nclass A {'), 'look: [code]');
    });

    test('inline code keeps its text and loses its backticks', () {
      expect(plainPreview('run `make test` now'), 'run make test now');
    });

    test('plain text is only flattened to one line', () {
      expect(plainPreview('one\ntwo  three'), 'one two three');
    });
  });

  testWidgets('a reply quote of a fenced message shows no backticks', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        ReplyQuote(
          resolved: message(
            id: 'parent',
            authorId: 'priya',
            authorDisplayName: 'Priya',
            content: _fenced,
          ),
          onTap: () {},
        ),
      ),
    );

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join(' ');
    expect(texts, contains('Here is the snippet I mean: [code]'));
    expect(texts, isNot(contains('`')));
  });
}
