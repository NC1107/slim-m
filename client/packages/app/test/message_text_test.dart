// SPDX-License-Identifier: Apache-2.0
/// Widget tests for [MessageBody]: fenced code renders through
/// [AppCodeBlock] and leaves the surrounding text and its existing inline
/// code/mention handling untouched.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/message_text.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _harness(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.light, AppTokens.light),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('plain content with no fence renders as before, with mentions '
      'and inline code intact', (tester) async {
    await tester.pumpWidget(
      _harness(
        const MessageBody(
          content: 'hey @nick, run `flutter test`',
          knownUsernames: {'nick'},
        ),
      ),
    );

    expect(find.byType(AppCodeBlock), findsNothing);
    expect(find.text('@nick'), findsOneWidget);
    expect(find.text('flutter test'), findsOneWidget);
  });

  testWidgets(
    '@everyone and @here render as mentions with no known usernames at all',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          const MessageBody(
            content: '@everyone please see @here for the update',
            knownUsernames: {},
          ),
        ),
      );

      expect(
        find.text('@everyone'),
        findsOneWidget,
        reason: 'reserved words render as mentions with no member list',
      );
      expect(find.text('@here'), findsOneWidget);
    },
  );

  testWidgets('an ordinary @name not in the known set stays plain text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const MessageBody(content: '@nobody is here', knownUsernames: {}),
      ),
    );

    // A mention chip is its own isolated `Text`; plain text only answers `find.text` on the whole sentence, never the bare token.
    expect(
      find.text('@nobody'),
      findsNothing,
      reason: '@nobody must not be mistaken for @everyone/@here',
    );
    expect(find.text('@nobody is here'), findsOneWidget);
  });

  testWidgets('a fenced block renders through AppCodeBlock with its language, '
      'and the surrounding text stays plain', (tester) async {
    await tester.pumpWidget(
      _harness(
        const MessageBody(
          content: 'before\n```dart\nfinal x = 1;\n```\nafter',
          knownUsernames: {},
        ),
      ),
    );

    expect(find.text('before'), findsOneWidget);
    expect(find.text('after'), findsOneWidget);

    final block = tester.widget<AppCodeBlock>(find.byType(AppCodeBlock));
    expect(block.language, 'dart');
    expect(block.lines, hasLength(1));
    expect(block.lines.single.spans.map((s) => s.text).join(), 'final x = 1;');
  });

  testWidgets('an unlabelled fence renders with a null language', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const MessageBody(content: '```\necho hi\n```', knownUsernames: {}),
      ),
    );

    final block = tester.widget<AppCodeBlock>(find.byType(AppCodeBlock));
    expect(block.language, isNull);
  });

  testWidgets('an empty fence renders a code block rather than throwing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(const MessageBody(content: '```\n```', knownUsernames: {})),
    );

    expect(find.byType(AppCodeBlock), findsOneWidget);
  });

  testWidgets(
    'an unterminated fence has nowhere to close, so it renders as plain '
    'text rather than hiding the rest of the message',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          const MessageBody(
            content: 'hi\n```js\nconsole.log(1)',
            knownUsernames: {},
          ),
        ),
      );

      expect(find.byType(AppCodeBlock), findsNothing);
      expect(find.textContaining('console.log(1)'), findsOneWidget);
    },
  );

  testWidgets('a very long code line scrolls horizontally instead of '
      'wrapping', (tester) async {
    final longLine = 'x' * 400;
    await tester.pumpWidget(
      _harness(
        MessageBody(content: '```\n$longLine\n```', knownUsernames: const {}),
      ),
    );

    final richTexts = tester.widgetList<RichText>(
      find.descendant(
        of: find.byType(AppCodeBlock),
        matching: find.byType(RichText),
      ),
    );
    expect(richTexts.any((r) => r.softWrap == false), isTrue);
  });
}
