// SPDX-License-Identifier: Apache-2.0
/// Tests for the message row: grouping must be visible in what actually
/// renders (the avatar and the gutter timestamp), not just in the flag
/// passed in, since that flag is exactly what a caller could get backwards.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/widgets/message_row.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

Message _message({
  String id = 'm1',
  String? authorId = 'author-1',
  String? authorDisplayName = 'Priya',
  int createdAt = 1700000000000,
  int? editedAt,
  bool pending = false,
  bool failed = false,
}) =>
    Message(
      id: id,
      channelId: 'c1',
      authorId: authorId,
      authorDisplayName: authorDisplayName,
      seq: 5,
      content: 'hello there',
      createdAt: createdAt,
      editedAt: editedAt,
      pending: pending,
      failed: failed,
    );

Widget _harness(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.light, AppTokens.light),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('an ungrouped row shows the avatar and the author name',
      (tester) async {
    await tester.pumpWidget(_harness(MessageRow(
      message: _message(),
      grouped: false,
      showNewDivider: false,
      knownUsernames: const {},
      onRetry: () {},
      onDiscard: () {},
      onQuickReact: () {},
      onReactionTap: (_) {},
      onVote: (_) {},
    )));

    expect(find.byType(AppAvatar), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);
  });

  testWidgets(
      'a grouped continuation drops the avatar and the name, and keeps '
      'the timestamp in the gutter instead', (tester) async {
    await tester.pumpWidget(_harness(MessageRow(
      message: _message(),
      grouped: true,
      showNewDivider: false,
      knownUsernames: const {},
      onRetry: () {},
      onDiscard: () {},
      onQuickReact: () {},
      onReactionTap: (_) {},
      onVote: (_) {},
    )));

    expect(find.byType(AppAvatar), findsNothing);
    expect(find.text('Priya'), findsNothing);
    // The gutter still carries a time, formatted the same way the header
    // line's own timestamp is.
    expect(find.text(formatMessageTime(1700000000000)), findsOneWidget);
  });

  testWidgets('the "New" divider only appears when asked for', (tester) async {
    await tester.pumpWidget(_harness(MessageRow(
      message: _message(),
      grouped: false,
      showNewDivider: true,
      knownUsernames: const {},
      onRetry: () {},
      onDiscard: () {},
      onQuickReact: () {},
      onReactionTap: (_) {},
      onVote: (_) {},
    )));
    expect(find.text('NEW'), findsOneWidget);

    await tester.pumpWidget(_harness(MessageRow(
      message: _message(),
      grouped: false,
      showNewDivider: false,
      knownUsernames: const {},
      onRetry: () {},
      onDiscard: () {},
      onQuickReact: () {},
      onReactionTap: (_) {},
      onVote: (_) {},
    )));
    expect(find.text('NEW'), findsNothing);
  });

  testWidgets('a webhook row shows a code-box leading glyph and the tag badge',
      (tester) async {
    await tester.pumpWidget(_harness(MessageRow(
      message: _message(authorDisplayName: 'CI Bot'),
      grouped: false,
      showNewDivider: false,
      knownUsernames: const {},
      onRetry: () {},
      onDiscard: () {},
      onQuickReact: () {},
      onReactionTap: (_) {},
      onVote: (_) {},
      isWebhook: true,
    )));

    expect(find.byType(AppAvatar), findsNothing);
    expect(find.byType(AppBadge), findsOneWidget);
    expect(find.text('CI Bot'), findsOneWidget);
  });

  testWidgets('a failed send shows the retry and discard actions',
      (tester) async {
    var retried = false;
    var discarded = false;
    await tester.pumpWidget(_harness(MessageRow(
      message: _message(failed: true),
      grouped: false,
      showNewDivider: false,
      knownUsernames: const {},
      onRetry: () => retried = true,
      onDiscard: () => discarded = true,
      onQuickReact: () {},
      onReactionTap: (_) {},
      onVote: (_) {},
    )));

    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Discard'));
    expect(retried, isTrue);
    expect(discarded, isTrue);
  });

  group('reactions', () {
    testWidgets('a chip shows the real count and reflects whether you reacted',
        (tester) async {
      await tester.pumpWidget(_harness(MessageRow(
        message: _message(),
        grouped: false,
        showNewDivider: false,
        knownUsernames: const {},
        onRetry: () {},
        onDiscard: () {},
        onQuickReact: () {},
        onReactionTap: (_) {},
        onVote: (_) {},
        reactions: const [
          // Escaped rather than literal: the hygiene gate forbids emoji
          // codepoints in client source, and these are user content standing in
          // for a reaction, not interface chrome.
          api.ReactionSummary(emoji: '\u{1F44D}', count: 3, reacted: true),
          api.ReactionSummary(emoji: '\u{1F389}', count: 1, reacted: false),
        ],
      )));

      expect(find.text('\u{1F44D}'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('\u{1F389}'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('tapping an existing chip reports which reaction was tapped',
        (tester) async {
      api.ReactionSummary? tapped;
      await tester.pumpWidget(_harness(MessageRow(
        message: _message(),
        grouped: false,
        showNewDivider: false,
        knownUsernames: const {},
        onRetry: () {},
        onDiscard: () {},
        onQuickReact: () {},
        onReactionTap: (r) => tapped = r,
        onVote: (_) {},
        reactions: const [
          api.ReactionSummary(emoji: '\u{1F44D}', count: 3, reacted: true),
        ],
      )));

      await tester.tap(find.text('\u{1F44D}'));
      expect(tapped?.emoji, '\u{1F44D}');
      expect(tapped?.reacted, isTrue);
    });
  });

  group('polls', () {
    api.Poll poll({int? votedOption, bool closed = false}) => api.Poll(
          question: 'Best editor?',
          options: const [
            api.PollOption(position: 0, label: 'Vim', votes: 2),
            api.PollOption(position: 1, label: 'Emacs', votes: 1),
          ],
          totalVotes: 3,
          votedOption: votedOption,
          closeAt: null,
          closed: closed,
        );

    testWidgets('renders the question and every option', (tester) async {
      await tester.pumpWidget(_harness(MessageRow(
        message: _message(),
        grouped: false,
        showNewDivider: false,
        knownUsernames: const {},
        onRetry: () {},
        onDiscard: () {},
        onQuickReact: () {},
        onReactionTap: (_) {},
        onVote: (_) {},
        poll: poll(),
      )));

      expect(find.text('Best editor?'), findsOneWidget);
      expect(find.text('Vim'), findsOneWidget);
      expect(find.text('Emacs'), findsOneWidget);
      expect(find.text('3 votes'), findsOneWidget);
    });

    testWidgets('tapping an option casts a vote for its position',
        (tester) async {
      int? voted;
      await tester.pumpWidget(_harness(MessageRow(
        message: _message(),
        grouped: false,
        showNewDivider: false,
        knownUsernames: const {},
        onRetry: () {},
        onDiscard: () {},
        onQuickReact: () {},
        onReactionTap: (_) {},
        onVote: (option) => voted = option,
        poll: poll(),
      )));

      await tester.tap(find.text('Emacs'));
      expect(voted, 1);
    });

    testWidgets('a closed poll does not accept a tap', (tester) async {
      int? voted;
      await tester.pumpWidget(_harness(MessageRow(
        message: _message(),
        grouped: false,
        showNewDivider: false,
        knownUsernames: const {},
        onRetry: () {},
        onDiscard: () {},
        onQuickReact: () {},
        onReactionTap: (_) {},
        onVote: (option) => voted = option,
        poll: poll(closed: true),
      )));

      await tester.tap(find.text('Vim'));
      expect(voted, isNull);
      expect(find.text('3 votes - closed'), findsOneWidget);
    });
  });

  testWidgets('attachments render through the provider-backed view',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: _harness(MessageRow(
          message: _message(),
          grouped: false,
          showNewDivider: false,
          knownUsernames: const {},
          onRetry: () {},
          onDiscard: () {},
          onQuickReact: () {},
          onReactionTap: (_) {},
          onVote: (_) {},
          attachments: const [
            api.Attachment(
              id: 'a1',
              filename: 'notes.txt',
              contentType: 'text/plain',
              size: 2048,
            ),
          ],
        )),
      ),
    );
    await tester.pump();

    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
  });
}
