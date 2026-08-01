// SPDX-License-Identifier: Apache-2.0
/// Widget tests for [MessageBody]'s new markdown rendering: inline styling,
/// spoilers, headings, quotes and lists, on top of the fenced-code and
/// mention/emoji handling `message_text_test.dart` already covers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/message_markdown_blocks.dart';
import 'package:slimm_app/src/widgets/message_spoiler.dart';
import 'package:slimm_app/src/widgets/message_text.dart';
import 'package:slimm_design_system/design_system.dart';

Widget _harness(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.light, AppTokens.light),
  home: Scaffold(body: child),
);

/// The [index]th `_MessageTextRun`'s own span tree, unwrapped past the extra
/// layer `Text.rich` adds: `Text.build()` wraps whatever span it is given in
/// `TextSpan(style: mergedStyle, children: [ourSpan])`, so `ourSpan` (what
/// `message_text.dart` actually built) is one level of `.children!.single`
/// deeper than the `RichText` widget's own `.text`.
TextSpan _messageSpan(WidgetTester tester, {int index = 0}) {
  final richTexts = tester
      .widgetList<RichText>(
        find.descendant(
          of: find.byType(MessageBody),
          matching: find.byType(RichText),
        ),
      )
      .toList();
  final outer = richTexts[index].text as TextSpan;
  return outer.children!.single as TextSpan;
}

void main() {
  testWidgets('bold renders with the semi weight', (tester) async {
    await tester.pumpWidget(
      _harness(const MessageBody(content: '**bold**', knownUsernames: {})),
    );
    final child = _messageSpan(tester).children!.single as TextSpan;
    expect(child.style!.fontWeight, AppWeights.semi);
    expect(child.toPlainText(), 'bold');
  });

  testWidgets('italic renders with an italic font style', (tester) async {
    await tester.pumpWidget(
      _harness(const MessageBody(content: '*italic*', knownUsernames: {})),
    );
    final child = _messageSpan(tester).children!.single as TextSpan;
    expect(child.style!.fontStyle, FontStyle.italic);
  });

  testWidgets('strikethrough renders with a line-through decoration', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(const MessageBody(content: '~~gone~~', knownUsernames: {})),
    );
    final child = _messageSpan(tester).children!.single as TextSpan;
    expect(child.style!.decoration, TextDecoration.lineThrough);
  });

  testWidgets('a spoiler hides its text behind a bar until tapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const MessageBody(content: 'it was ||him||', knownUsernames: {}),
      ),
    );

    expect(find.byType(MessageSpoiler), findsOneWidget);
    // The text is present but invisible; the bar is what proves it is hidden.
    expect(
      find.descendant(
        of: find.byType(MessageSpoiler),
        matching: find.byType(DecoratedBox),
      ),
      findsOneWidget,
    );
    final hiddenOpacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(MessageSpoiler),
        matching: find.byType(Opacity),
      ),
    );
    expect(hiddenOpacity.opacity, 0);

    await tester.tap(find.byType(MessageSpoiler));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(MessageSpoiler),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
    final revealedOpacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(MessageSpoiler),
        matching: find.byType(Opacity),
      ),
    );
    expect(revealedOpacity.opacity, 1);
  });

  testWidgets('tapping a revealed spoiler hides it again', (tester) async {
    await tester.pumpWidget(
      _harness(const MessageBody(content: '||toggle||', knownUsernames: {})),
    );
    await tester.tap(find.byType(MessageSpoiler));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(MessageSpoiler),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );

    await tester.tap(find.byType(MessageSpoiler));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(MessageSpoiler),
        matching: find.byType(DecoratedBox),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a heading renders at a larger type size than a paragraph', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const MessageBody(
          content: '# Big\n\nordinary text',
          knownUsernames: {},
        ),
      ),
    );

    final headingStyle = _messageSpan(tester, index: 0).style!;
    expect(headingStyle.fontSize, AppText.title.fontSize);
    expect(headingStyle.fontWeight, AppWeights.semi);
  });

  testWidgets('a quote renders inside MarkdownQuote with a left rule', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(const MessageBody(content: '> quoted text', knownUsernames: {})),
    );
    expect(find.byType(MarkdownQuote), findsOneWidget);
    expect(find.textContaining('quoted text'), findsOneWidget);
  });

  testWidgets('a bullet list renders through MarkdownList with both items', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const MessageBody(content: '- first\n- second', knownUsernames: {}),
      ),
    );
    expect(find.byType(MarkdownList), findsOneWidget);
    expect(find.textContaining('first'), findsOneWidget);
    expect(find.textContaining('second'), findsOneWidget);
  });

  testWidgets('mentions and inline code still work inside a plain paragraph '
      'alongside the new inline parser', (tester) async {
    await tester.pumpWidget(
      _harness(
        const MessageBody(
          content: 'hey @nick, run `flutter test`',
          knownUsernames: {'nick'},
        ),
      ),
    );
    expect(find.text('@nick'), findsOneWidget);
    expect(find.text('flutter test'), findsOneWidget);
  });

  testWidgets('a mention still resolves correctly when it sits inside bold '
      'text', (tester) async {
    await tester.pumpWidget(
      _harness(
        const MessageBody(content: '**@nick**', knownUsernames: {'nick'}),
      ),
    );
    expect(find.text('@nick'), findsOneWidget);
  });
}
